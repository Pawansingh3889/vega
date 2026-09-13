import React from 'react';
import { Button } from '@/components/ui/button';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { ChevronsUpDown } from 'lucide-react';

interface SearchableComboboxProps {
  value?: string;
  onSelect: (value: string) => void;
  placeholder: string;
  searchPlaceholder: string;
  options: { id: string; name: string; subtitle?: string; keywords?: string[] }[];
  disabled?: boolean;
  loading?: boolean;
  emptyMessage?: string;
  className?: string;
}

export function SearchableCombobox({
  value,
  onSelect,
  placeholder,
  searchPlaceholder,
  options,
  disabled = false,
  loading = false,
  emptyMessage = "No options available",
  className = ""
}: SearchableComboboxProps) {
  const [open, setOpen] = React.useState(false);
  const [searchValue, setSearchValue] = React.useState("");
  const inputRef = React.useRef<HTMLInputElement>(null);

  React.useEffect(() => {
    if (open) {
      // Reset and focus input on open
      setSearchValue("");
      setTimeout(() => inputRef.current?.focus(), 0);
    }
  }, [open]);

  const normalize = (str?: string) => (str || "").toLowerCase().normalize('NFKD').replace(/\p{Diacritic}/gu, '').trim();

  const filteredOptions = React.useMemo(() => {
    const q = normalize(searchValue);
    if (!q) return options;
    return options.filter(option => {
      const name = normalize(option.name);
      const subtitle = normalize(option.subtitle);
      const keywords = (option.keywords || []).map(normalize).join(' ');
      const haystack = `${name} ${subtitle} ${keywords}`;
      return haystack.includes(q);
    });
  }, [options, searchValue]);

  const selectedOption = options.find(option => option.id === value);

  const getDisplayText = () => {
    if (selectedOption) return selectedOption.name;
    if (loading) return "Loading...";
    return placeholder;
  };

  const isButtonDisabled = disabled || loading;

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          role="combobox"
          aria-expanded={open}
          className={`w-full justify-between h-9 ${className}`}
          disabled={isButtonDisabled}
        >
          {getDisplayText()}
          <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
        </Button>
      </PopoverTrigger>
      <PopoverContent 
        className="z-[9999] pointer-events-auto w-[var(--radix-popover-trigger-width)] min-w-[20rem] p-0 bg-popover shadow-lg border rounded-md"
        align="start"
        sideOffset={4}
      >
        <Command className="bg-popover">
          <CommandInput 
            ref={inputRef}
            placeholder={searchPlaceholder}
            value={searchValue}
            onValueChange={(v) => { console.debug("Supplier combobox search:", v); setSearchValue(v); }}
            autoFocus
          />
          <CommandList>
            {loading ? (
              <div className="py-6 text-center text-sm text-muted-foreground">
                Loading options...
              </div>
            ) : options.length === 0 ? (
              <CommandEmpty>{emptyMessage}</CommandEmpty>
            ) : filteredOptions.length === 0 ? (
              <CommandEmpty>No results found.</CommandEmpty>
            ) : (
              <CommandGroup>
                {filteredOptions.map((option) => (
                  <CommandItem
                    key={option.id}
                    value={option.id}
                    onSelect={() => {
                      onSelect(option.id);
                      setOpen(false);
                      setSearchValue("");
                    }}
                    className="cursor-pointer hover:bg-accent hover:text-accent-foreground"
                  >
                    <div className="flex flex-col">
                      <span>{option.name}</span>
                      {option.subtitle && (
                        <span className="text-sm text-muted-foreground">{option.subtitle}</span>
                      )}
                    </div>
                  </CommandItem>
                ))}
              </CommandGroup>
            )}
          </CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  );
}