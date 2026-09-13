// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.56.0';

const securityHeaders = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'X-XSS-Protection': '1; mode=block',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};

function getCorsHeaders(req: Request) {
  const origin = req.headers.get('origin') || '*';
  
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    ...securityHeaders,
  };
}

const LOVABLE_API_KEY = Deno.env.get('LOVABLE_API_KEY');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
// Demoted from service-role: this function has the caller's JWT and can act as them.
//
// This function holds the caller's JWT and reads customers, payments, products
// and companies, all of which RLS already scopes to the caller's company.
// Running it as service-role bypassed that scoping for no gain: an assistant
// answering questions about your own company does not need to be able to read
// everyone's.
//
// It also removes a sharper problem. companyId arrives in the request BODY,
// which the client controls, and every query then ran with a credential that
// ignores policies. The company check below was the only thing between a
// forged companyId and another tenant's data. Acting as the caller means the
// database enforces the boundary whether or not that check is right.
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req);
  
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Verify authentication (JWT is automatically validated by Supabase)
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ 
        error: 'Authentication required',
        response: 'Please log in to use the AI assistant.' 
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const { message, companyId, userId } = await req.json();

    if (!LOVABLE_API_KEY) {
      throw new Error('Lovable API key not configured');
    }

    // Act as the caller. Every query below now runs under the caller's own
    // policies, and the x-vega-company header is forwarded so the session
    // company context resolves the same way it does for the browser.
    const companyHeader = req.headers.get('x-vega-company');
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: {
        headers: {
          Authorization: authHeader,
          ...(companyHeader ? { 'x-vega-company': companyHeader } : {}),
        },
      },
      auth: { persistSession: false },
    });
    
    // Verify user has access to this company
    const token = authHeader.replace('Bearer ', '');
    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    
    if (userError || !userData.user) {
      console.error('User verification failed:', userError);
      return new Response(JSON.stringify({ 
        error: 'Invalid authentication',
        response: 'Please log in again to continue.' 
      }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    
    // Verify user belongs to the requested company
    const { data: profile } = await supabase
      .from('profiles')
      .select('company_id')
      .eq('user_id', userData.user.id)
      .single();
    
    if (!profile || profile.company_id !== companyId) {
      console.error('Unauthorized company access attempt');
      return new Response(JSON.stringify({ 
        error: 'Unauthorized',
        response: 'You do not have access to this company data.' 
      }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Check user has admin or owner role (AI assistant requires elevated permissions)
    const { data: roleData, error: roleError } = await supabase
      .from('user_roles')
      .select('role')
      .eq('user_id', userData.user.id)
      .maybeSingle();
    
    if (roleError || !roleData || !['owner', 'admin'].includes(roleData.role)) {
      console.error('Insufficient permissions for AI assistant - user role:', roleData?.role);
      return new Response(JSON.stringify({ 
        error: 'Insufficient permissions',
        response: 'AI Assistant is only available to company administrators and owners. Please contact your administrator for access.' 
      }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Verify company has appropriate subscription for AI features
    const { data: company, error: companyError } = await supabase
      .from('companies')
      .select('subscription_plan, subscription_status')
      .eq('id', companyId)
      .single();
    
    if (companyError || !company) {
      console.error('Company lookup failed:', companyError);
      return new Response(JSON.stringify({ 
        error: 'Company not found',
        response: 'Unable to verify company subscription. Please try again.' 
      }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Check subscription plan (AI is available to all active companies)
    // Allow all subscription plans including null/undefined for businesses without explicit plan
    console.log('Company subscription - plan:', company.subscription_plan, 'status:', company.subscription_status);

    // Check subscription is active
    if (company.subscription_status && company.subscription_status !== 'active' && company.subscription_status !== 'trial') {
      console.log('AI access denied - subscription status:', company.subscription_status);
      return new Response(JSON.stringify({ 
        error: 'Subscription inactive',
        response: 'Your subscription is not active. Please contact support or renew your subscription to continue using AI Assistant.' 
      }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    console.log('Processing business query:', message);
    console.log('Company ID:', companyId);
    console.log('User ID:', userData.user.id);

    // Check if user wants conversation history
    if (message.toLowerCase().includes('conversation history') || message.toLowerCase().includes('chat history') || message.toLowerCase().includes('previous messages')) {
      const conversationHistory = await getConversationHistory(supabase, companyId, userId);
      return new Response(JSON.stringify({
        response: "Here are your recent conversations:",
        data: conversationHistory,
        queryType: 'conversation_history',
        tableData: formatConversationHistory(conversationHistory)
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Determine the type of query and generate appropriate SQL
    const queryAnalysis = await analyzeBusinessQuery(message);
    console.log('Query analysis:', queryAnalysis);

    let data = null;
    let queryResult = null;

    // Execute the appropriate database query based on the analysis
    if (queryAnalysis.queryType === 'sales_quantities') {
      queryResult = await executeSalesQuantityQuery(supabase, companyId, queryAnalysis);
    } else if (queryAnalysis.queryType === 'sales_orders') {
      queryResult = await executeQuery(supabase, companyId, queryAnalysis, 'sales_orders');
  } else if (queryAnalysis.queryType === 'purchase_invoices') {
      queryResult = await executeQuery(supabase, companyId, queryAnalysis, 'sales_invoices');
    } else if (queryAnalysis.queryType === 'customers') {
      queryResult = await executeQuery(supabase, companyId, queryAnalysis, 'customers');
    } else if (queryAnalysis.queryType === 'suppliers') {
      queryResult = await executeQuery(supabase, companyId, queryAnalysis, 'suppliers');
    } else if (queryAnalysis.queryType === 'products') {
      queryResult = await executeQuery(supabase, companyId, queryAnalysis, 'products');
    } else if (queryAnalysis.queryType === 'inventory') {
      queryResult = await executeInventoryQuery(supabase, companyId, queryAnalysis);
    } else if (queryAnalysis.queryType === 'payments') {
      queryResult = await executePaymentQuery(supabase, companyId, queryAnalysis);
    } else if (queryAnalysis.queryType === 'analytics') {
      queryResult = await executeAnalyticsQuery(supabase, companyId, queryAnalysis);
    } else if (queryAnalysis.queryType === 'actions') {
      queryResult = await executeActionQuery(supabase, companyId, queryAnalysis);
    } else {
      // Enhanced general business insights
      queryResult = await getEnhancedBusinessInsights(supabase, companyId);
    }

    if (queryResult.error) {
      throw new Error(`Database query failed: ${queryResult.error.message}`);
    }

    data = queryResult.data;

    // Filter data to show only essential fields
    const filteredData = filterEssentialData(data, queryAnalysis.queryType);

    // Generate AI response using Gemini
    const aiResponse = await generateGeminiResponse(message, filteredData, queryAnalysis);

    // Store conversation in history
    await storeConversationHistory(supabase, companyId, userId, message, aiResponse);

    return new Response(JSON.stringify({
      response: aiResponse,
      data: filteredData,
      queryType: queryAnalysis.queryType,
      tableData: formatTableData(filteredData, queryAnalysis.queryType)
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Error in gemini-business-assistant:', error);
    return new Response(JSON.stringify({ 
      error: error.message,
      response: "I'm sorry, I encountered an error while processing your request. Please try again."
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});

async function analyzeBusinessQuery(message: string) {
  const lowerMessage = message.toLowerCase();
  
  // Enhanced query classification with better pattern matching
  if (lowerMessage.includes('sales qty') || lowerMessage.includes('sales quantity') || 
      lowerMessage.includes('sold qty') || lowerMessage.includes('sold quantity') || 
      lowerMessage.includes('quantity sold') || (lowerMessage.includes('sales') && lowerMessage.includes('qty'))) {
    return {
      queryType: 'sales_quantities',
      timeframe: extractTimeframe(lowerMessage),
      status: extractStatus(lowerMessage),
      limit: extractLimit(lowerMessage),
      analytics: extractAnalytics(lowerMessage),
      month: extractMonth(lowerMessage),
      stockLevel: extractStockLevel(lowerMessage)
    };
  } else if (lowerMessage.includes('sales order') || lowerMessage.includes('order') || 
      lowerMessage.includes('so ') || (lowerMessage.includes('sale') && !lowerMessage.includes('qty'))) {
    return {
      queryType: 'sales_orders',
      timeframe: extractTimeframe(lowerMessage),
      status: extractStatus(lowerMessage),
      limit: extractLimit(lowerMessage),
      analytics: extractAnalytics(lowerMessage)
    };
  } else if (lowerMessage.includes('purchase') || lowerMessage.includes('invoice') || 
             lowerMessage.includes('pi ') || lowerMessage.includes('buy') ||
             lowerMessage.includes('procurement')) {
    return {
      queryType: 'purchase_invoices',
      timeframe: extractTimeframe(lowerMessage),
      status: extractStatus(lowerMessage),
      limit: extractLimit(lowerMessage),
      analytics: extractAnalytics(lowerMessage)
    };
  } else if (lowerMessage.includes('customer') || lowerMessage.includes('client') ||
             lowerMessage.includes('buyer')) {
    return {
      queryType: 'customers',
      limit: extractLimit(lowerMessage),
      analytics: extractAnalytics(lowerMessage)
    };
  } else if (lowerMessage.includes('supplier') || lowerMessage.includes('vendor') ||
             lowerMessage.includes('seller')) {
    return {
      queryType: 'suppliers',
      limit: extractLimit(lowerMessage),
      analytics: extractAnalytics(lowerMessage)
    };
  } else if (lowerMessage.includes('product') || lowerMessage.includes('inventory') || 
             lowerMessage.includes('stock') || lowerMessage.includes('item') ||
             lowerMessage.includes('sku')) {
    return {
      queryType: 'inventory',
      stockLevel: extractStockLevel(lowerMessage),
      limit: extractLimit(lowerMessage),
      analytics: extractAnalytics(lowerMessage)
    };
  } else if (lowerMessage.includes('payment') || lowerMessage.includes('receivable') ||
             lowerMessage.includes('payable') || lowerMessage.includes('aging') ||
             lowerMessage.includes('outstanding')) {
    return {
      queryType: 'payments',
      timeframe: extractTimeframe(lowerMessage),
      limit: extractLimit(lowerMessage),
      analytics: extractAnalytics(lowerMessage)
    };
  } else if (lowerMessage.includes('report') || lowerMessage.includes('kpi') ||
             lowerMessage.includes('metric') || lowerMessage.includes('trend') ||
             lowerMessage.includes('performance') || lowerMessage.includes('dashboard')) {
    return {
      queryType: 'analytics',
      timeframe: extractTimeframe(lowerMessage),
      limit: extractLimit(lowerMessage),
      analytics: extractAnalytics(lowerMessage)
    };
  } else if (lowerMessage.includes('email') || lowerMessage.includes('trigger') ||
             lowerMessage.includes('send') || lowerMessage.includes('notify')) {
    return {
      queryType: 'actions',
      action: extractAction(lowerMessage),
      limit: extractLimit(lowerMessage)
    };
  } else {
    return {
      queryType: 'general',
      limit: 10
    };
  }
}

function extractTimeframe(message: string) {
  if (message.includes('today') || message.includes('this day')) return 1;
  if (message.includes('yesterday')) return 1;
  if (message.includes('last week') || message.includes('7 days') || message.includes('this week')) return 7;
  if (message.includes('last month') || message.includes('30 days') || message.includes('this month')) return 30;
  if (message.includes('last 15 days') || message.includes('15 days') || message.includes('half month')) return 15;
  if (message.includes('last 3 months') || message.includes('90 days') || message.includes('quarter')) return 90;
  if (message.includes('last 6 months') || message.includes('180 days') || message.includes('half year')) return 180;
  if (message.includes('last year') || message.includes('365 days') || message.includes('12 months')) return 365;
  
  // Extract custom number of days
  const dayMatch = message.match(/(\d+)\s*days?/);
  if (dayMatch) return Math.min(parseInt(dayMatch[1]), 365);
  
  return null;
}

function extractStatus(message: string) {
  if (message.includes('pending') || message.includes('waiting')) return 'pending';
  if (message.includes('completed') || message.includes('finished') || message.includes('done')) return 'completed';
  if (message.includes('draft') || message.includes('unpublished')) return 'draft';
  if (message.includes('invoiced') || message.includes('billed')) return 'invoiced';
  if (message.includes('received') || message.includes('delivered')) return 'received';
  if (message.includes('cancelled') || message.includes('canceled')) return 'cancelled';
  return null;
}

function extractStockLevel(message: string) {
  if (message.includes('low stock') || message.includes('reorder') || message.includes('minimum')) return 'low';
  if (message.includes('out of stock') || message.includes('zero stock') || message.includes('empty')) return 'out';
  if (message.includes('high stock') || message.includes('excess') || message.includes('overstocked')) return 'high';
  return null;
}

function extractAnalytics(message: string) {
  const analytics = [];
  if (message.includes('total') || message.includes('sum') || message.includes('amount')) analytics.push('total');
  if (message.includes('average') || message.includes('avg') || message.includes('mean')) analytics.push('average');
  if (message.includes('count') || message.includes('number') || message.includes('quantity')) analytics.push('count');
  if (message.includes('trend') || message.includes('growth') || message.includes('change')) analytics.push('trend');
  if (message.includes('top') || message.includes('best') || message.includes('highest')) analytics.push('top');
  if (message.includes('bottom') || message.includes('worst') || message.includes('lowest')) analytics.push('bottom');
  return analytics.length > 0 ? analytics : null;
}

function extractAction(message: string) {
  if (message.includes('email') || message.includes('send mail')) return 'email';
  if (message.includes('notify') || message.includes('alert')) return 'notify';
  if (message.includes('trigger') || message.includes('execute')) return 'trigger';
  return null;
}

function extractLimit(message: string) {
  const match = message.match(/(\d+)/);
  return match ? Math.min(parseInt(match[1]), 100) : 15; // Increased default and max
}

function extractMonth(message: string) {
  const lowerMessage = message.toLowerCase();
  if (lowerMessage.includes('sep') || lowerMessage.includes('september')) return 9;
  if (lowerMessage.includes('jan') || lowerMessage.includes('january')) return 1;
  if (lowerMessage.includes('feb') || lowerMessage.includes('february')) return 2;
  if (lowerMessage.includes('mar') || lowerMessage.includes('march')) return 3;
  if (lowerMessage.includes('apr') || lowerMessage.includes('april')) return 4;
  if (lowerMessage.includes('may')) return 5;
  if (lowerMessage.includes('jun') || lowerMessage.includes('june')) return 6;
  if (lowerMessage.includes('jul') || lowerMessage.includes('july')) return 7;
  if (lowerMessage.includes('aug') || lowerMessage.includes('august')) return 8;
  if (lowerMessage.includes('oct') || lowerMessage.includes('october')) return 10;
  if (lowerMessage.includes('nov') || lowerMessage.includes('november')) return 11;
  if (lowerMessage.includes('dec') || lowerMessage.includes('december')) return 12;
  return null;
}

async function executeQuery(supabase: any, companyId: string, analysis: any, table: string) {
  let query = supabase.from(table).select('*').eq('company_id', companyId);

  // Apply timeframe filter
  if (analysis.timeframe) {
    const dateField = table === 'sales_orders' ? 'order_date' : 
                     table === 'sales_invoices' ? 'invoice_date' : 'created_at';
    const date = new Date();
    date.setDate(date.getDate() - analysis.timeframe);
    query = query.gte(dateField, date.toISOString().split('T')[0]);
  }

  // Apply status filter
  if (analysis.status) {
    query = query.eq('status', analysis.status);
  }

  // Apply limit and order
  query = query.order('created_at', { ascending: false }).limit(analysis.limit || 10);

  return await query;
}

async function executeInventoryQuery(supabase: any, companyId: string, analysis: any) {
  let query = supabase.from('products').select('*').eq('company_id', companyId);

  if (analysis.stockLevel === 'low') {
    // Use a raw query to properly compare numeric columns
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .eq('company_id', companyId)
      .filter('stock_quantity', 'lte', 'min_stock_level')
      .order('stock_quantity', { ascending: true })
      .limit(analysis.limit || 15);
    
    // If the filter doesn't work, fallback to manual filtering
    if (error || !data) {
      const allProducts = await supabase
        .from('products')
        .select('*')
        .eq('company_id', companyId)
        .order('stock_quantity', { ascending: true });
      
      if (allProducts.data) {
        const lowStockProducts = allProducts.data.filter(product => 
          product.stock_quantity <= product.min_stock_level
        ).slice(0, analysis.limit || 15);
        
        return { data: lowStockProducts, error: null };
      }
    }
    
    return { data, error };
  } else if (analysis.stockLevel === 'out') {
    query = query.eq('stock_quantity', 0);
  } else if (analysis.stockLevel === 'high') {
    // Products where stock is significantly higher than min level
    const allProducts = await supabase
      .from('products')
      .select('*')
      .eq('company_id', companyId);
    
    if (allProducts.data) {
      const highStockProducts = allProducts.data.filter(product => 
        product.stock_quantity >= (product.min_stock_level * 3)
      ).slice(0, analysis.limit || 15);
      
      return { data: highStockProducts, error: null };
    }
  }

  query = query.order('stock_quantity', { ascending: true }).limit(analysis.limit || 15);
  return await query;
}

async function executeSalesQuantityQuery(supabase: any, companyId: string, analysis: any) {
  try {
    let whereClause = `si.company_id = '${companyId}'`;
    
    // Add month filter
    if (analysis.month) {
      whereClause += ` AND EXTRACT(MONTH FROM si.invoice_date) = ${analysis.month}`;
    }
    
    // Add status filter to only include finalized invoices
    whereClause += ` AND si.status = 'finalized'`;
    
    let query = `
      SELECT 
        p.name as product_name,
        p.sku as product_sku,
        p.stock_quantity as current_stock,
        p.min_stock_level,
        SUM(sii.quantity_invoiced) as total_sales_qty,
        COUNT(si.id) as sales_count,
        AVG(sii.unit_price) as avg_unit_price,
        SUM(sii.quantity_invoiced * sii.unit_price) as total_sales_value
      FROM products p
      LEFT JOIN sales_invoice_items sii ON p.id = sii.product_id
      LEFT JOIN sales_invoices si ON sii.sales_invoice_id = si.id AND ${whereClause}
      WHERE p.company_id = '${companyId}'
    `;
    
    // Add low stock filter if requested
    if (analysis.stockLevel === 'low') {
      query += ` AND p.stock_quantity <= p.min_stock_level`;
    }
    
    query += `
      GROUP BY p.id, p.name, p.sku, p.stock_quantity, p.min_stock_level
      HAVING SUM(sii.quantity_invoiced) > 0 OR p.stock_quantity <= p.min_stock_level
      ORDER BY p.stock_quantity ASC, total_sales_qty DESC
      LIMIT ${analysis.limit || 15}
    `;

    const { data, error } = await supabase.rpc('execute_raw_sql', { query });
    
    if (error) {
      console.error('SQL Query Error:', error);
      // Fallback to simpler query
      return await executeSalesQuantityFallback(supabase, companyId, analysis);
    }

    return { data, error };
  } catch (error) {
    console.error('Sales quantity query error:', error);
    return await executeSalesQuantityFallback(supabase, companyId, analysis);
  }
}

async function executeSalesQuantityFallback(supabase: any, companyId: string, analysis: any) {
  // Get low stock products
  const { data: lowStockProducts } = await supabase
    .from('products')
    .select('id, name, sku, stock_quantity, min_stock_level')
    .eq('company_id', companyId)
    .filter('stock_quantity', 'lte', 'min_stock_level')
    .order('stock_quantity', { ascending: true })
    .limit(analysis.limit || 15);

  if (!lowStockProducts?.length) {
    return { data: [], error: null };
  }

  // Get sales data for these products
  const productIds = lowStockProducts.map(p => p.id);
  
  let invoiceQuery = supabase
    .from('sales_invoices')
    .select('id, invoice_date, status')
    .eq('company_id', companyId)
    .eq('status', 'finalized');
    
  if (analysis.month) {
    const year = new Date().getFullYear();
    const startDate = new Date(year, analysis.month - 1, 1);
    const endDate = new Date(year, analysis.month, 0);
    invoiceQuery = invoiceQuery
      .gte('invoice_date', startDate.toISOString().split('T')[0])
      .lte('invoice_date', endDate.toISOString().split('T')[0]);
  }

  const { data: invoices } = await invoiceQuery;
  
  if (!invoices?.length) {
    // Return products with zero sales
    return {
      data: lowStockProducts.map(p => ({
        product_name: p.name,
        product_sku: p.sku,
        current_stock: p.stock_quantity,
        min_stock_level: p.min_stock_level,
        total_sales_qty: 0,
        sales_count: 0,
        avg_unit_price: 0,
        total_sales_value: 0
      })),
      error: null
    };
  }

  const invoiceIds = invoices.map(i => i.id);
  
  const { data: salesItems } = await supabase
    .from('sales_invoice_items')
    .select('product_id, quantity_invoiced, unit_price')
    .in('sales_invoice_id', invoiceIds)
    .in('product_id', productIds);

  // Aggregate the results
  const results = lowStockProducts.map(product => {
    const productSales = salesItems?.filter(item => item.product_id === product.id) || [];
    const totalQty = productSales.reduce((sum, item) => sum + item.quantity_invoiced, 0);
    const totalValue = productSales.reduce((sum, item) => sum + (item.quantity_invoiced * item.unit_price), 0);
    const avgPrice = totalQty > 0 ? totalValue / totalQty : 0;

    return {
      product_name: product.name,
      product_sku: product.sku,
      current_stock: product.stock_quantity,
      min_stock_level: product.min_stock_level,
      total_sales_qty: totalQty,
      sales_count: productSales.length,
      avg_unit_price: avgPrice,
      total_sales_value: totalValue
    };
  });

  return { data: results, error: null };
}

async function executePaymentQuery(supabase: any, companyId: string, analysis: any) {
  let query = supabase.from('payments').select('*').eq('company_id', companyId);
  
  if (analysis.timeframe) {
    const date = new Date();
    date.setDate(date.getDate() - analysis.timeframe);
    query = query.gte('payment_date', date.toISOString().split('T')[0]);
  }
  
  query = query.order('payment_date', { ascending: false }).limit(analysis.limit || 15);
  return await query;
}

async function executeAnalyticsQuery(supabase: any, companyId: string, analysis: any) {
  // Get comprehensive analytics data
  const [salesStats, purchaseStats, customerStats, productStats] = await Promise.all([
    supabase.from('sales_orders').select('total_amount, status, order_date').eq('company_id', companyId),
    supabase.from('sales_invoices').select('total_amount, status, invoice_date').eq('company_id', companyId),
    supabase.from('customers').select('id, name, is_active').eq('company_id', companyId),
    supabase.from('products').select('stock_quantity, unit_price, cost_price').eq('company_id', companyId)
  ]);

  return {
    data: {
      sales_analytics: salesStats.data || [],
      invoice_analytics: purchaseStats.data || [],
      customer_analytics: customerStats.data || [],
      product_analytics: productStats.data || []
    },
    error: null
  };
}

async function executeActionQuery(supabase: any, companyId: string, analysis: any) {
  // Handle action-based queries (like email triggers)
  return {
    data: {
      action: analysis.action,
      message: "Action queries are informational only. I can provide guidance on implementing automated workflows."
    },
    error: null
  };
}

async function getEnhancedBusinessInsights(supabase: any, companyId: string) {
  // Get comprehensive business data with analytics
  const [salesResult, purchaseResult, customerResult, productResult, paymentResult] = await Promise.all([
    supabase.from('sales_orders').select('id, total_amount, status, order_date').eq('company_id', companyId).order('order_date', { ascending: false }).limit(10),
    supabase.from('sales_invoices').select('id, total_amount, status, invoice_date').eq('company_id', companyId).order('invoice_date', { ascending: false }).limit(10),
    supabase.from('customers').select('id, name, is_active, credit_limit').eq('company_id', companyId).limit(10),
    supabase.from('products').select('id, name, stock_quantity, min_stock_level, unit_price').eq('company_id', companyId).limit(10),
    supabase.from('payments').select('id, amount, payment_date, payment_method').eq('company_id', companyId).order('payment_date', { ascending: false }).limit(5)
  ]);

  // Calculate basic analytics
  const salesData = salesResult.data || [];
  const purchaseData = purchaseResult.data || [];
  const productData = productResult.data || [];
  
  const totalSales = salesData.reduce((sum, order) => sum + (order.total_amount || 0), 0);
  const totalPurchases = purchaseData.reduce((sum, invoice) => sum + (invoice.total_amount || 0), 0);
  const lowStockCount = productData.filter(product => product.stock_quantity <= product.min_stock_level).length;

  return {
    data: {
      sales_orders: salesData,
      sales_invoices: purchaseData,
      customers: customerResult.data || [],
      products: productData,
      payments: paymentResult.data || [],
      analytics: {
        total_sales: totalSales,
        total_purchases: totalPurchases,
        low_stock_items: lowStockCount,
        active_customers: (customerResult.data || []).filter(c => c.is_active).length
      }
    },
    error: null
  };
}

async function generateGeminiResponse(message: string, data: any, analysis: any) {
  // Return ONLY structured table data - no text response
  const systemPrompt = `You are a data processor. Return ONLY "TABLE_DATA_ONLY" as response. 
  CRITICAL RULES:
  - Do NOT return any text, explanations, or formatted data
  - Do NOT create table markdown or any text output
  - Return EXACTLY this text: "TABLE_DATA_ONLY"
  - The table will be generated automatically from the data
  - No other text is allowed`;

  const userPrompt = `User Query: "${message}"
  Data: ${JSON.stringify(data)}
  
  Return only: TABLE_DATA_ONLY`;

  const response = await fetch('https://ai.gateway.lovable.dev/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${LOVABLE_API_KEY}`,
    },
    body: JSON.stringify({
      model: 'google/gemini-2.5-flash',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt }
      ],
      max_tokens: 50,
      temperature: 0.0,
    }),
  });

  console.log('Lovable AI response status:', response.status, response.statusText);

  if (!response.ok) {
    const errorText = await response.text();
    console.error('Lovable AI HTTP error:', response.status, response.statusText);
    console.error('Lovable AI error response:', errorText);
    
    if (response.status === 429) {
      throw new Error('Rate limit exceeded. Please try again in a moment.');
    }
    if (response.status === 402) {
      throw new Error('AI credits exhausted. Please add credits to continue using the AI assistant.');
    }
    throw new Error(`Lovable AI HTTP error: ${response.status} ${response.statusText}`);
  }

  const result = await response.json();
  console.log('Lovable AI response:', result);
  
  if (result.error) {
    console.error('Lovable AI error:', result.error);
    throw new Error(`Lovable AI error: ${result.error.message || JSON.stringify(result.error)}`);
  }
  
  // Always return table-only indicator - the actual table is generated from data
  return "TABLE_DATA_ONLY";
}

// Filter data to show only essential fields
function filterEssentialData(data: any, queryType: string) {
  if (!data) return data;

  if (Array.isArray(data)) {
    return data.slice(0, 10).map(item => {
      switch (queryType) {
        case 'sales_quantities':
          return {
            product_name: item.product_name,
            product_sku: item.product_sku,
            current_stock: item.current_stock,
            min_stock_level: item.min_stock_level,
            total_sales_qty: item.total_sales_qty,
            total_sales_value: item.total_sales_value
          };
        case 'sales_orders':
          return {
            order_number: item.order_number,
            status: item.status,
            total_amount: item.total_amount,
            order_date: item.order_date
          };
        case 'inventory':
          return {
            name: item.name,
            sku: item.sku,
            stock_quantity: item.stock_quantity,
            min_stock_level: item.min_stock_level
          };
        case 'customers':
          return {
            name: item.name,
            email: item.email,
            is_active: item.is_active
          };
        default:
          // Return first 4 properties for other types
          const keys = Object.keys(item).slice(0, 4);
          const filtered = {};
          keys.forEach(key => filtered[key] = item[key]);
          return filtered;
      }
    });
  }

  return data;
}

// Store conversation history
async function storeConversationHistory(supabase: any, companyId: string, userId: string, userMessage: string, aiResponse: string) {
  try {
    const { error } = await supabase
      .from('ai_conversation_history')
      .insert({
        company_id: companyId,
        user_id: userId,
        user_message: userMessage,
        ai_response: aiResponse,
        created_at: new Date().toISOString()
      });

    if (error) {
      console.log('Note: Could not store conversation history (table may not exist):', error.message);
    }
  } catch (error) {
    console.log('Note: Conversation history storage failed (expected if table not created)');
  }
}

// Get conversation history for last 24 hours
async function getConversationHistory(supabase: any, companyId: string, userId: string) {
  try {
    const twentyFourHoursAgo = new Date();
    twentyFourHoursAgo.setHours(twentyFourHoursAgo.getHours() - 24);

    const { data, error } = await supabase
      .from('ai_conversation_history')
      .select('user_message, ai_response, created_at')
      .eq('company_id', companyId)
      .eq('user_id', userId)
      .gte('created_at', twentyFourHoursAgo.toISOString())
      .order('created_at', { ascending: false })
      .limit(20);

    if (error) {
      console.log('Could not fetch conversation history:', error.message);
      return [];
    }

    return data || [];
  } catch (error) {
    console.log('Conversation history fetch failed');
    return [];
  }
}

// Format conversation history for display
function formatConversationHistory(history: any[]) {
  if (!history || history.length === 0) {
    return {
      columns: ['Message', 'Response', 'Time'],
      rows: [['No recent conversations', '', '']]
    };
  }

  return {
    columns: ['Your Message', 'AI Response', 'Time'],
    rows: history.map((item: any) => [
      item.user_message?.substring(0, 50) + '...' || 'N/A',
      item.ai_response?.substring(0, 50) + '...' || 'N/A',
      new Date(item.created_at).toLocaleString()
    ])
  };
}

function formatTableData(data: any, queryType: string) {
  if (!data || (Array.isArray(data) && data.length === 0)) {
    return null;
  }

  // Handle enhanced general insights data
  if (queryType === 'general' && data.sales_orders) {
    const analytics = data.analytics || {};
    return {
      columns: ['Metric', 'Value', 'Details', 'Status'],
      rows: [
        ['Total Sales', `₹${analytics.total_sales?.toLocaleString() || '0'}`, `${data.sales_orders.length} orders`, 'Active'],
        ['Total Purchases', `₹${analytics.total_purchases?.toLocaleString() || '0'}`, `${data.purchase_invoices.length} invoices`, 'Active'],
        ['Active Customers', analytics.active_customers || '0', `${data.customers.length} total`, 'Engaged'],
        ['Low Stock Items', analytics.low_stock_items || '0', `${data.products.length} total products`, analytics.low_stock_items > 0 ? 'Alert' : 'Good'],
        ['Recent Payments', data.payments.length || '0', 'Last 5 transactions', 'Processing']
      ]
    };
  }

  // Handle analytics data
  if (queryType === 'analytics') {
    const salesData = data.sales_analytics || [];
    const purchaseData = data.purchase_analytics || [];
    const customerData = data.customer_analytics || [];
    const productData = data.product_analytics || [];
    
    const totalSalesRevenue = salesData.reduce((sum: number, item: any) => sum + (item.total_amount || 0), 0);
    const totalPurchaseCost = purchaseData.reduce((sum: number, item: any) => sum + (item.total_amount || 0), 0);
    const grossMargin = totalSalesRevenue - totalPurchaseCost;
    const avgOrderValue = salesData.length > 0 ? totalSalesRevenue / salesData.length : 0;

    return {
      columns: ['KPI', 'Value', 'Count', 'Performance'],
      rows: [
        ['Sales Revenue', `₹${totalSalesRevenue.toLocaleString()}`, `${salesData.length} orders`, 'Strong'],
        ['Purchase Cost', `₹${totalPurchaseCost.toLocaleString()}`, `${purchaseData.length} invoices`, 'Managed'],
        ['Gross Margin', `₹${grossMargin.toLocaleString()}`, 'Revenue - Cost', grossMargin > 0 ? 'Positive' : 'Negative'],
        ['Avg Order Value', `₹${avgOrderValue.toLocaleString()}`, 'Per transaction', 'Metric'],
        ['Active Customers', customerData.filter((c: any) => c.is_active).length.toString(), `${customerData.length} total`, 'Engaged']
      ]
    };
  }

  // Handle payment data
  if (queryType === 'payments') {
    return {
      columns: ['Payment ID', 'Amount', 'Date', 'Method', 'Status'],
      rows: data.map((item: any) => [
        `PAY-${item.id.slice(-6)}`,
        `₹${item.amount?.toLocaleString() || '0'}`,
        new Date(item.payment_date).toLocaleDateString(),
        item.payment_method || 'N/A',
        'Processed'
      ])
    };
  }

  if (!Array.isArray(data) || data.length === 0) {
    return null;
  }

  // Enhanced formatting based on query type
  switch (queryType) {
    case 'sales_orders':
      return {
        columns: ['Order #', 'Customer', 'Date', 'Amount', 'Status'],
        rows: data.map((item: any) => [
          item.order_number || 'N/A',
          item.customer_name || 'N/A',
          new Date(item.order_date).toLocaleDateString(),
          `₹${item.total_amount?.toLocaleString() || '0'}`,
          item.status || 'N/A'
        ])
      };

    case 'purchase_invoices':
      return {
        columns: ['Invoice #', 'Supplier', 'Date', 'Amount', 'Status'],
        rows: data.map((item: any) => [
          item.purchase_invoice_number || 'N/A',
          item.supplier_id || 'N/A',
          new Date(item.purchase_invoice_date).toLocaleDateString(),
          `₹${item.total_amount?.toLocaleString() || '0'}`,
          item.status || 'N/A'
        ])
      };

    case 'customers':
      return {
        columns: ['Name', 'Email', 'Phone', 'Credit Limit', 'Status'],
        rows: data.map((item: any) => [
          item.name || 'N/A',
          item.email || 'N/A',
          item.phone || 'N/A',
          item.credit_limit ? `₹${item.credit_limit.toLocaleString()}` : 'N/A',
          item.is_active ? 'Active' : 'Inactive'
        ])
      };

    case 'suppliers':
      return {
        columns: ['Name', 'Contact Person', 'Email', 'Phone', 'GST'],
        rows: data.map((item: any) => [
          item.name || 'N/A',
          item.contact_person || 'N/A',
          item.email || 'N/A',
          item.phone || 'N/A',
          item.gst_number || 'N/A'
        ])
      };

      return {
        columns: ['Product Name', 'SKU', 'Current Stock', 'Min Level', 'Unit Price', 'Status'],
        rows: data.map((item: any) => {
          const stockStatus = item.stock_quantity <= item.min_stock_level ? 'Low Stock' : 
                             item.stock_quantity === 0 ? 'Out of Stock' : 'In Stock';
          return [
            item.name || 'N/A',
            item.sku || 'N/A',
            item.stock_quantity?.toString() || '0',
            item.min_stock_level?.toString() || '0',
            `₹${item.unit_price?.toLocaleString() || '0'}`,
            stockStatus
          ];
        })
      };

    case 'sales_quantities':
      return {
        columns: ['Product Name', 'SKU', 'Current Stock', 'Min Level', 'Sales Qty', 'Sales Value'],
        rows: data.map((item: any) => [
          item.product_name || 'N/A',
          item.product_sku || 'N/A',
          item.current_stock?.toString() || '0',
          item.min_stock_level?.toString() || '0',
          item.total_sales_qty?.toString() || '0',
          `₹${item.total_sales_value?.toLocaleString() || '0'}`
        ])
      };

    case 'actions':
      return {
        columns: ['Action Type', 'Description', 'Implementation', 'Notes'],
        rows: [
          [data.action || 'General', 'Business Process Automation', 'Custom Development', data.message || 'Contact support for implementation']
        ]
      };

    case 'conversation_history':
      return formatConversationHistory(data);

    default:
      return null;
  }
}