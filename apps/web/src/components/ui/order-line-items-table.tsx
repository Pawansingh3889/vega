import React from 'react';
import { Control, UseFieldArrayReturn, FieldErrors } from 'react-hook-form';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { SearchableCombobox } from '@/components/ui/searchable-combobox';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { FormControl, FormField, FormItem, FormMessage } from '@/components/ui/form';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ShoppingCart, Plus, Trash2 } from 'lucide-react';
import { cn } from '@/lib/utils';

interface Product {
  id: string;
  name: string;
  sku?: string;
  unit_price?: number;
  gst_percentage?: number;
  hsn_sac_code?: string;
  unit_of_measure?: string;
}

interface OrderLineItemsTableProps {
  control: Control<any>;
  fieldsArray: UseFieldArrayReturn<any, 'items', 'id'>;
  products: Product[];
  globalGstType: 'intra' | 'inter';
  onGstTypeChange: (type: 'intra' | 'inter') => void;
  onAddItem: () => void;
  onProductSelect: (index: number, productId: string) => void;
  onCalculateLineAmounts: (index: number) => void;
  onValidateGSTRate?: (index: number, type: string, rate: number) => boolean;
  readOnly?: boolean;
  currency?: string;
  errors?: FieldErrors<any>;
}

export function OrderLineItemsTable({
  control,
  fieldsArray,
  products,
  globalGstType,
  onGstTypeChange,
  onAddItem,
  onProductSelect,
  onCalculateLineAmounts,
  onValidateGSTRate,
  readOnly = false,
  currency = '₹',
  errors: _errors
}: OrderLineItemsTableProps) {
  const { fields, remove } = fieldsArray;

  // Transform products for SearchableCombobox
  const productOptions = products.map(product => ({
    id: product.id,
    name: product.name,
    subtitle: `${product.sku ? product.sku + ' | ' : ''}${currency}${product.unit_price || 0} | GST: ${product.gst_percentage || 0}%`,
    keywords: [product.sku, product.name].filter(Boolean) as string[]
  }));

  const gstRateOptions = [
    { value: "0", label: "0%" },
    { value: "2.5", label: "2.5%" },
    { value: "6", label: "6%" },
    { value: "9", label: "9%" },
    { value: "14", label: "14%" },
    { value: "18", label: "18%" },
    { value: "28", label: "28%" }
  ];

  return (
    <Card className="shadow-sm border-border/50">
      <CardHeader className="pb-4">
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
          <CardTitle className="text-lg font-semibold flex items-center gap-2">
            <ShoppingCart className="h-5 w-5 text-primary" />
            Order Line Items
          </CardTitle>
          
          <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3 w-full sm:w-auto">
            {/* GST Type Toggle */}
            <div className="flex items-center gap-2">
              <Button
                type="button"
                variant={globalGstType === 'intra' ? 'default' : 'outline'}
                size="sm"
                onClick={() => onGstTypeChange('intra')}
                className="h-8 text-xs px-3"
                disabled={readOnly}
              >
                Intra-State (CGST + SGST)
              </Button>
              <Button
                type="button"
                variant={globalGstType === 'inter' ? 'default' : 'outline'}
                size="sm"
                onClick={() => onGstTypeChange('inter')}
                className="h-8 text-xs px-3"
                disabled={readOnly}
              >
                Inter-State (IGST)
              </Button>
            </div>

            {/* Add Item Button */}
            {!readOnly && (
              <Button 
                type="button" 
                onClick={onAddItem} 
                size="sm" 
                className="h-8 gap-2 whitespace-nowrap"
              >
                <Plus className="h-4 w-4" />
                Add Item
              </Button>
            )}
          </div>
        </div>
      </CardHeader>

      <CardContent className="p-0">
        <div className="overflow-x-auto">
          <Table>
            <TableHeader className="bg-muted/30">
              <TableRow className="hover:bg-muted/30">
                <TableHead className="w-[250px] font-semibold text-sm">Product *</TableHead>
                <TableHead className="w-[100px] text-center font-semibold text-sm">HSN/SAC *</TableHead>
                <TableHead className="w-[80px] text-center font-semibold text-sm">Qty *</TableHead>
                <TableHead className="w-[150px] text-center font-semibold text-sm">Unit Price *</TableHead>
                
                {globalGstType === 'intra' ? (
                  <>
                    <TableHead className="w-[80px] text-center font-semibold text-sm">CGST%</TableHead>
                    <TableHead className="w-[80px] text-center font-semibold text-sm">SGST%</TableHead>
                  </>
                ) : (
                  <TableHead className="w-[80px] text-center font-semibold text-sm">IGST%</TableHead>
                )}
                
                <TableHead className="w-[80px] text-center font-semibold text-sm">Disc%</TableHead>
                <TableHead className="w-[100px] text-right font-semibold text-sm">Disc Value</TableHead>
                <TableHead className="w-[100px] text-right font-semibold text-sm">GST Value</TableHead>
                <TableHead className="w-[120px] text-right font-semibold text-sm">Line Total</TableHead>
                
                {!readOnly && <TableHead className="w-[50px]"></TableHead>}
              </TableRow>
            </TableHeader>

            <TableBody>
              {fields.length === 0 ? (
                <TableRow>
                  <TableCell 
                    colSpan={globalGstType === 'intra' ? (readOnly ? 10 : 11) : (readOnly ? 9 : 10)} 
                    className="text-center py-8 text-muted-foreground"
                  >
                    No items added yet. Click "Add Item" to get started.
                  </TableCell>
                </TableRow>
              ) : (
                fields.map((field, index) => {
                  return (
                    <TableRow key={field.id} className={cn(
                      "group hover:bg-muted/20 transition-colors",
                      index % 2 === 0 ? 'bg-background' : 'bg-muted/10'
                    )}>
                      {/* Product Selection */}
                      <TableCell className="p-2">
                        <FormField
                          control={control}
                          name={`items.${index}.product_id`}
                          render={({ field, fieldState }) => (
                            <FormItem>
                              <FormControl>
                                <div className={cn(fieldState.error && "ring-2 ring-destructive rounded-md")}>
                                  <SearchableCombobox
                                    value={field.value}
                                    onSelect={(value) => onProductSelect(index, value)}
                                    placeholder="Select product"
                                    searchPlaceholder="Search products..."
                                    options={productOptions}
                                    disabled={readOnly}
                                    className={cn(
                                      "h-9 text-sm",
                                      fieldState.error && "border-destructive"
                                    )}
                                  />
                                </div>
                              </FormControl>
                              <FormMessage />
                            </FormItem>
                          )}
                        />
                      </TableCell>

                      {/* HSN/SAC Code */}
                      <TableCell className="p-2">
                        <FormField
                          control={control}
                          name={`items.${index}.hsn_sac_code`}
                          render={({ field, fieldState }) => (
                            <FormItem>
                              <FormControl>
                                <Input 
                                  type="text" 
                                  placeholder="HSN/SAC"
                                  readOnly={true}
                                  className={cn(
                                    "h-9 w-full text-center text-sm bg-muted/50 cursor-not-allowed",
                                    fieldState.error && "border-destructive focus-visible:ring-destructive"
                                  )}
                                  {...field}
                                  disabled={readOnly}
                                />
                              </FormControl>
                              <FormMessage />
                            </FormItem>
                          )}
                        />
                      </TableCell>

                      {/* Quantity */}
                      <TableCell className="p-2">
                        <FormField
                          control={control}
                          name={`items.${index}.quantity`}
                          render={({ field, fieldState }) => (
                            <FormItem>
                              <FormControl>
                                <Input 
                                  type="number" 
                                  min="0" 
                                  step="1"
                                  className={cn(
                                    "h-9 w-24 text-center text-sm",
                                    fieldState.error && "border-destructive focus-visible:ring-destructive"
                                  )}
                                  value={field.value ?? ''}
                                  onChange={(e) => {
                                    const value = e.target.valueAsNumber;
                                    field.onChange(isNaN(value) ? 0 : value);
                                    onCalculateLineAmounts(index);
                                  }}
                                  onBlur={field.onBlur}
                                  disabled={readOnly}
                                />
                              </FormControl>
                              {/* Stock Level Display */}
                              <div className="text-xs text-center mt-1">
                                <span className="font-medium text-muted-foreground">
                                  Available: {control._formValues?.items?.[index]?.stock_on_hand || 0} units
                                </span>
                              </div>
                              <FormMessage />
                            </FormItem>
                          )}
                        />
                      </TableCell>

                      {/* Unit Price */}
                      <TableCell className="p-2">
                        <FormField
                          control={control}
                          name={`items.${index}.unit_price`}
                          render={({ field, fieldState }) => (
                            <FormItem>
                              <FormControl>
                                <Input 
                                  type="number" 
                                  step="0.01" 
                                  min="0" 
                                  className={cn(
                                    "h-9 w-full text-right text-sm bg-accent/10 border-accent/20",
                                    fieldState.error && "border-destructive focus-visible:ring-destructive"
                                  )}
                                  {...field}
                                  onChange={(e) => {
                                    field.onChange(parseFloat(e.target.value) || 0);
                                    onCalculateLineAmounts(index);
                                  }}
                                  disabled={readOnly}
                                />
                              </FormControl>
                              <FormMessage />
                            </FormItem>
                          )}
                        />
                      </TableCell>

                      {/* GST Rate Fields */}
                      {globalGstType === 'intra' ? (
                        <>
                          {/* CGST Rate */}
                          <TableCell className="p-2">
                            <FormField
                              control={control}
                              name={`items.${index}.cgst_rate`}
                              render={({ field }) => (
                                <FormItem>
                                  <FormControl>
                                    <Select 
                                      value={field.value?.toString() || "0"}
                                      onValueChange={(value) => {
                                        const rate = parseFloat(value);
                                        if (!onValidateGSTRate || onValidateGSTRate(index, 'cgst', rate)) {
                                          field.onChange(rate);
                                          onCalculateLineAmounts(index);
                                        }
                                      }}
                                      disabled={readOnly}
                                    >
                                      <SelectTrigger className="h-9 text-sm">
                                        <SelectValue placeholder="0%" />
                                      </SelectTrigger>
                                      <SelectContent className="bg-background border shadow-md">
                                        {gstRateOptions.map((option) => (
                                          <SelectItem key={option.value} value={option.value}>
                                            {option.label}
                                          </SelectItem>
                                        ))}
                                      </SelectContent>
                                    </Select>
                                  </FormControl>
                                  <FormMessage />
                                </FormItem>
                              )}
                            />
                          </TableCell>

                          {/* SGST Rate */}
                          <TableCell className="p-2">
                            <FormField
                              control={control}
                              name={`items.${index}.sgst_rate`}
                              render={({ field }) => (
                                <FormItem>
                                  <FormControl>
                                    <Select 
                                      value={field.value?.toString() || "0"}
                                      onValueChange={(value) => {
                                        const rate = parseFloat(value);
                                        if (!onValidateGSTRate || onValidateGSTRate(index, 'sgst', rate)) {
                                          field.onChange(rate);
                                          onCalculateLineAmounts(index);
                                        }
                                      }}
                                      disabled={readOnly}
                                    >
                                      <SelectTrigger className="h-9 text-sm">
                                        <SelectValue placeholder="0%" />
                                      </SelectTrigger>
                                      <SelectContent className="bg-background border shadow-md">
                                        {gstRateOptions.map((option) => (
                                          <SelectItem key={option.value} value={option.value}>
                                            {option.label}
                                          </SelectItem>
                                        ))}
                                      </SelectContent>
                                    </Select>
                                  </FormControl>
                                  <FormMessage />
                                </FormItem>
                              )}
                            />
                          </TableCell>
                        </>
                      ) : (
                        /* IGST Rate */
                        <TableCell className="p-2">
                          <FormField
                            control={control}
                            name={`items.${index}.igst_rate`}
                            render={({ field }) => (
                              <FormItem>
                                <FormControl>
                                  <Select 
                                    value={field.value?.toString() || "0"}
                                    onValueChange={(value) => {
                                      const rate = parseFloat(value);
                                      if (!onValidateGSTRate || onValidateGSTRate(index, 'igst', rate)) {
                                        field.onChange(rate);
                                        onCalculateLineAmounts(index);
                                      }
                                    }}
                                    disabled={readOnly}
                                  >
                                    <SelectTrigger className="h-9 text-sm">
                                      <SelectValue placeholder="0%" />
                                    </SelectTrigger>
                                    <SelectContent className="bg-background border shadow-md">
                                      {gstRateOptions.map((option) => (
                                        <SelectItem key={option.value} value={option.value}>
                                          {option.label}
                                        </SelectItem>
                                      ))}
                                    </SelectContent>
                                  </Select>
                                </FormControl>
                                <FormMessage />
                              </FormItem>
                            )}
                          />
                        </TableCell>
                      )}

                      {/* Discount Percentage */}
                      <TableCell className="p-2">
                        <FormField
                          control={control}
                          name={`items.${index}.discount_percentage`}
                          render={({ field }) => (
                            <FormItem>
                              <FormControl>
                                <Input 
                                  type="number" 
                                  step="0.01" 
                                  min="0" 
                                  max="100"
                                  className="h-9 w-full text-center text-sm bg-accent/10 border-accent/20" 
                                  {...field}
                                  onChange={(e) => {
                                    field.onChange(parseFloat(e.target.value) || 0);
                                    onCalculateLineAmounts(index);
                                  }}
                                  disabled={readOnly}
                                />
                              </FormControl>
                              <FormMessage />
                            </FormItem>
                          )}
                        />
                      </TableCell>

                      {/* Discount Value - Calculated */}
                      <TableCell className="p-2 text-right">
                        <FormField
                          control={control}
                          name={`items.${index}.discount_amount`}
                          render={({ field }) => (
                            <div className="text-sm font-medium text-muted-foreground bg-muted/20 rounded px-2 py-1.5 min-h-[36px] flex items-center justify-end">
                              {currency}{Math.round(field.value || 0)}
                            </div>
                          )}
                        />
                      </TableCell>

                      {/* GST Value - Calculated */}
                      <TableCell className="p-2 text-right">
                        <FormField
                          control={control}
                          name={`items.${index}.cgst_amount`}
                          render={() => {
                            const cgstAmount = control._formValues?.items?.[index]?.cgst_amount || 0;
                            const sgstAmount = control._formValues?.items?.[index]?.sgst_amount || 0;
                            const igstAmount = control._formValues?.items?.[index]?.igst_amount || 0;
                            const totalGstAmount = cgstAmount + sgstAmount + igstAmount;
                            
                            return (
                              <div className="text-sm font-medium text-muted-foreground bg-muted/20 rounded px-2 py-1.5 min-h-[36px] flex items-center justify-end">
                                {currency}{Math.round(totalGstAmount)}
                              </div>
                            );
                          }}
                        />
                      </TableCell>

                      {/* Line Total - Calculated */}
                      <TableCell className="p-2 text-right">
                        <FormField
                          control={control}
                          name={`items.${index}.total_price`}
                          render={({ field }) => (
                            <div className="text-sm font-semibold text-foreground bg-primary/5 rounded px-2 py-1.5 min-h-[36px] flex items-center justify-end border border-primary/20">
                              {currency}{Math.round(field.value || 0)}
                            </div>
                          )}
                        />
                      </TableCell>

                      {/* Delete Button */}
                      {!readOnly && (
                        <TableCell className="p-2">
                          <Button
                            type="button"
                            variant="ghost"
                            size="sm"
                            onClick={() => remove(index)}
                            className="h-8 w-8 p-0 text-destructive hover:text-destructive hover:bg-destructive/10 opacity-0 group-hover:opacity-100 transition-opacity"
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </TableCell>
                      )}
                    </TableRow>
                  );
                })
              )}
            </TableBody>
          </Table>
        </div>

        {/* Summary Bar */}
        {fields.length > 0 && (
          <div className="border-t bg-muted/10 px-4 py-3">
            <div className="flex justify-end">
              <div className="text-sm text-muted-foreground">
                <Badge variant="secondary" className="mr-2">
                  {fields.length} item{fields.length !== 1 ? 's' : ''}
                </Badge>
                Total items ready for processing
              </div>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}