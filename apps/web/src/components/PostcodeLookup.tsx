/**
 * Look up a UK postcode and hand the caller whichever address is picked.
 *
 * Deliberately owns no form fields itself. It only knows how to turn a
 * postcode into a list of candidates and report the one chosen; what those
 * become (address line 1, town, county, ...) is the caller's business, so
 * this drops into any form without knowing its field names in advance.
 *
 * Not wired into a page yet. GatedBusinessRegistration.tsx is the only
 * address-entry surface in the app today, and it is unauthenticated (a new
 * business creating its account has no session), while
 * /api/v1/postcode/lookup requires one. Built and tested standalone, ready
 * for the first signed-in form that needs it.
 */

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2, Search } from 'lucide-react';
import { lookupPostcode, PostcodeApiError, type PostcodeAddress } from '@/lib/postcode';

interface PostcodeLookupProps {
  onSelect: (address: PostcodeAddress) => void;
  /** Distinguishes multiple instances on one page for label/id association. */
  id?: string;
}

export function PostcodeLookup({ onSelect, id = 'postcode-lookup' }: PostcodeLookupProps) {
  const [postcode, setPostcode] = useState('');
  const [addresses, setAddresses] = useState<PostcodeAddress[] | null>(null);
  const [isSearching, setIsSearching] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const search = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = postcode.trim();
    if (!trimmed) return;

    setIsSearching(true);
    setError(null);
    setAddresses(null);
    try {
      const result = await lookupPostcode(trimmed);
      setAddresses(result.addresses);
    } catch (err) {
      // The service writes not_configured, malformed and not_found to be read
      // by a person, so a PostcodeApiError's own message is shown. Anything
      // else (network refusal, a CSP gap, the class of failure #144 and #147
      // were) gets a message that says so rather than "undefined".
      console.error('[PostcodeLookup] search failed:', err);
      setError(
        err instanceof PostcodeApiError
          ? err.message
          : 'Could not reach the postcode lookup service.',
      );
    } finally {
      setIsSearching(false);
    }
  };

  const handleSelect = (address: PostcodeAddress) => {
    onSelect(address);
    // Collapses back to the input rather than staying open on a stale list:
    // picking one is the end of this interaction, and the caller's own form
    // now holds the result.
    setAddresses(null);
  };

  return (
    <div className="space-y-2">
      <form onSubmit={search} className="flex gap-2 items-end">
        <div className="flex-1 space-y-2">
          <Label htmlFor={id}>Postcode</Label>
          <Input
            id={id}
            value={postcode}
            onChange={(e) => setPostcode(e.target.value)}
            placeholder="HX7 6AB"
            autoComplete="postal-code"
          />
        </div>
        <Button type="submit" variant="secondary" disabled={isSearching || !postcode.trim()}>
          {isSearching ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <>
              <Search className="h-4 w-4 mr-2" />
              Find address
            </>
          )}
        </Button>
      </form>

      {error !== null && <p className="text-sm text-destructive">{error}</p>}

      {addresses !== null && addresses.length === 0 && (
        <p className="text-sm text-muted-foreground">
          No addresses found for that postcode. Enter it manually below.
        </p>
      )}

      {addresses !== null && addresses.length > 0 && (
        <div className="space-y-2">
          <Label htmlFor={`${id}-results`}>
            {addresses.length} address{addresses.length === 1 ? '' : 'es'} found
          </Label>
          <select
            id={`${id}-results`}
            className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
            defaultValue=""
            onChange={(e) => {
              const chosen = addresses.find((a) => a.formatted_address === e.target.value);
              if (chosen) handleSelect(chosen);
            }}
          >
            <option value="" disabled>
              Choose an address
            </option>
            {addresses.map((a) => (
              <option key={a.formatted_address} value={a.formatted_address}>
                {a.formatted_address}
              </option>
            ))}
          </select>
        </div>
      )}
    </div>
  );
}
