-- Enable realtime for sales tables
ALTER TABLE public.sales_invoices REPLICA IDENTITY FULL;
ALTER TABLE public.sales_invoice_items REPLICA IDENTITY FULL;
ALTER TABLE public.sales_orders REPLICA IDENTITY FULL;
ALTER TABLE public.sales_order_items REPLICA IDENTITY FULL;

-- Add tables to realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.sales_invoices;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sales_invoice_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sales_orders;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sales_order_items;