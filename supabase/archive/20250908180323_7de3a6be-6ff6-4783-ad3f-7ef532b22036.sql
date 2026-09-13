-- Add missing foreign key constraints to enable proper joins

-- Add foreign key from grn_header to purchase_orders
ALTER TABLE public.grn_header 
ADD CONSTRAINT fk_grn_header_purchase_order 
FOREIGN KEY (purchase_order_id) REFERENCES public.purchase_orders(id) ON DELETE SET NULL;

-- Add foreign key from grn_header to suppliers  
ALTER TABLE public.grn_header 
ADD CONSTRAINT fk_grn_header_supplier 
FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE CASCADE;

-- Add foreign key from sales_invoices to customers
ALTER TABLE public.sales_invoices 
ADD CONSTRAINT fk_sales_invoices_customer 
FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;

-- Add foreign key from debit_notes to suppliers
ALTER TABLE public.debit_notes 
ADD CONSTRAINT fk_debit_notes_supplier 
FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE CASCADE;

-- Add foreign key from return_order_header to customers  
ALTER TABLE public.return_order_header 
ADD CONSTRAINT fk_return_order_header_customer 
FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;