// Directory badges a listing needs on our site, shown in a closed "Featured on" panel at the bottom of
// the footer. The links stay in the served HTML (for a directory's verifier and for crawlers) while a
// visitor sees one collapsed line. Only directories FLP MARKETING has cleared go in (reputable ones
// only). Keep each link followed: some verifiers reject nofollow.
// Shape: { name, href, img?, width?, height? }
export const BADGES = [
  // Findly.tools (DR 82), requested 2026-11-27: free dofollow listing once its badge checker finds this on the homepage.
  { name: "Featured on Findly.tools", href: "https://findly.tools/ai-usage-menu?utm_source=aiusagemenu", img: "https://findly.tools/badges/findly-tools-badge-light.svg", width: 175, height: 55 },
];
