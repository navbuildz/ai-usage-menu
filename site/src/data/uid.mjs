// Unique ids for inline SVG gradients, stable for a given build order.
let n = 0;
export const uid = (prefix='u') => prefix + (++n).toString(36);
