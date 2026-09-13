import React, { useState, useEffect } from 'react';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { supabase } from '@/integrations/supabase/client';

interface ProductSelectorProps {
  value?: string;
  onChange: (value: string) => void;
}

export function ProductSelector({ value = "all", onChange }: ProductSelectorProps) {
  const [products, setProducts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchProducts = async () => {
      try {
        console.log('ProductSelector: Fetching products...');
        const { data, error } = await supabase
          .from('products')
          .select('id, name, sku')
          .eq('is_active', true)
          .order('name');

        if (error) throw error;
        console.log('ProductSelector: Products fetched:', data?.length || 0);
        setProducts(data || []);
      } catch (error) {
        console.error('ProductSelector: Error fetching products:', error);
      } finally {
        setLoading(false);
      }
    };

    fetchProducts();
  }, []);

  // Set default value to "all" if not provided
  useEffect(() => {
    if (!value && !loading) {
      onChange("all");
    }
  }, [value, onChange, loading]);

  console.log('ProductSelector: Current value:', value, 'Products available:', products.length);

  return (
    <Select value={value || "all"} onValueChange={(val) => {
      console.log('ProductSelector: Value changed to:', val);
      onChange(val);
    }}>
      <SelectTrigger className="bg-background border-input">
        <SelectValue placeholder={loading ? "Loading products..." : "Select product..."} />
      </SelectTrigger>
      <SelectContent className="bg-background border-input shadow-lg z-50">
        <SelectItem value="all" className="bg-background hover:bg-accent">
          All Products (Summary View)
        </SelectItem>
        {products.map((product) => (
          <SelectItem key={product.id} value={product.id} className="bg-background hover:bg-accent">
            {product.name} ({product.sku}) - Customer Breakdown
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}