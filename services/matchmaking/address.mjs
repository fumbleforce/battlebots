import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';

// The HTTPS hostname can retain IPv6. Native ENet assignments use the public
// IPv4 address explicitly so the client cannot choose an unsupported AAAA route.
export async function resolveGameAddress(address, resolve = lookup) {
  if (typeof address !== 'string' || !address || address.length > 253 || /[\s/:]/.test(address)) {
    throw new Error('Invalid public game address');
  }
  if (isIP(address) === 4) return address;
  try {
    const result = await resolve(address, { family: 4 });
    if (result.family !== 4 || isIP(result.address) !== 4) throw new Error();
    return result.address;
  } catch {
    // Do not carry resolver error details, hostnames or configured paths into logs.
    throw new Error('Public game IPv4 address unavailable');
  }
}
