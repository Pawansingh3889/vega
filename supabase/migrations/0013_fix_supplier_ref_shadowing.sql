-- You cannot insert a supplier.
--
-- generate_supplier_ref declares a local variable called supplier_ref, then
-- ends with:
--
--   WHILE EXISTS (SELECT 1 FROM public.suppliers WHERE supplier_ref = final_ref)
--
-- PL/pgSQL cannot tell whether that name means the variable or the column, so
-- every insert into suppliers fails with 42702, "column reference is ambiguous".
-- The trigger auto_generate_supplier_ref fires on every row, so the table is
-- unusable rather than merely fragile.
--
-- Two changes, both minimal: the variable is renamed to configured_ref, and the
-- column reference is table-qualified so the name can never be ambiguous again
-- regardless of what someone declares later. The sibling generators
-- (generate_po_number, generate_so_number, generate_rso_number) already qualify
-- theirs and are left alone.
--
-- Found by loading the seed dataset, not by any schema check: the function is
-- perfectly valid SQL until something calls it.

CREATE OR REPLACE FUNCTION public.generate_supplier_ref(supplier_name text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    config_record RECORD;
    configured_ref TEXT;
    comp_id UUID;
    first_four_letters TEXT;
    date_part TEXT;
    ref_no TEXT;
    counter INTEGER := 1;
    final_ref TEXT;
BEGIN
    SELECT public.user_company_id() INTO comp_id;

    SELECT * INTO config_record
    FROM public.document_format_configs
    WHERE company_id = comp_id
      AND document_type = 'supplier_id'
      AND is_active = true
    LIMIT 1;

    IF FOUND THEN
        configured_ref := config_record.prefix || config_record.current_counter;

        UPDATE public.document_format_configs
        SET current_counter = current_counter + 1,
            updated_at = now()
        WHERE id = config_record.id;

        RETURN configured_ref;
    END IF;

    first_four_letters := UPPER(SUBSTRING(REGEXP_REPLACE(supplier_name, '[^A-Za-z]', '', 'g') FROM 1 FOR 4));

    WHILE LENGTH(first_four_letters) < 4 LOOP
        first_four_letters := first_four_letters || 'X';
    END LOOP;

    date_part := to_char(NOW(), 'DDMMYYYY');
    ref_no := first_four_letters || date_part;
    final_ref := ref_no;

    WHILE EXISTS (SELECT 1 FROM public.suppliers s WHERE s.supplier_ref = final_ref) LOOP
        final_ref := ref_no || '-' || LPAD(counter::TEXT, 2, '0');
        counter := counter + 1;
    END LOOP;

    RETURN final_ref;
END;
$$;

-- A supplier must be insertable. Proving it rather than assuming the rename was
-- enough.
--
-- The probe runs inside a subtransaction and is rolled back by a sentinel
-- exception rather than deleted afterwards. Deleting does not work: audit
-- triggers write transaction_audit_log rows that hold a foreign key back to
-- companies, so tidying up fails on the reference. A BEGIN/EXCEPTION block in
-- PL/pgSQL is a subtransaction, so raising inside it undoes everything without
-- touching the outer migration.
DO $$
BEGIN
  BEGIN
    DECLARE
      comp uuid;
    BEGIN
      INSERT INTO public.companies (name) VALUES ('__probe company__') RETURNING id INTO comp;
      INSERT INTO public.suppliers (company_id, name) VALUES (comp, '__probe supplier__');
    END;
    RAISE EXCEPTION 'vega_probe_rollback';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM <> 'vega_probe_rollback' THEN RAISE; END IF;
  END;
END
$$;
