import config from './repo.json' with {type:'json'};
import {readRepository} from './repository.mjs';
export const stats = await readRepository(config);
export const repo = 'https://github.com/'+config.owner+'/'+config.repo;
export const base = 'https://aiusagemenu.com';
export const compatibility='Works with Claude Pro, Max and Team plans and ChatGPT plans for Codex. API-key accounts have no plan limits to show.';
export const labels={home:'Home','claude-code-usage':'Claude Code usage','codex-usage':'Codex usage','claude-usage-limits':'Claude usage limits','open-source':'Open source',privacy:'Privacy & Legal',compare:'Compare',download:'Download'};
export const pathFor=id=>id==='home'?'/':'/'+id;
export const dates=Object.fromEntries(Object.keys(labels).map(id=>[id,'2026-11-23']));
export const visuals={
  'hero-dark':'Claude Code usage window beside the live menu bar gauge and Dock donut on a dark Mac desktop',
  'hero-light':'Claude Code usage window, menu bar gauge and Dock icon on a light Mac desktop',
  trio:'AI Usage Menu Dock gauges at 30%, 72% and 94% usage',
  pair:'Claude Code and Codex usage windows showing session and weekly limits',
  terminal:'Claude Code /usage output alongside the same limits in AI Usage Menu',
  breakdown:'Contributing activity ranked by request share in the Claude Code tab',
  privacy:'Local data flow from Claude Code and Codex into AI Usage Menu',
  code:'Swift source files for the local Claude Code and Codex readers',
  compare:'Comparison of data sources used by Mac usage trackers',
  onboarding:'First launch of AI Usage Menu on macOS',
  'strips-dark':'Menu bar gauges on a dark desktop at healthy, near-limit and critical usage',
  'strips-light':'Menu bar gauges on a light desktop at healthy, near-limit and critical usage'
};
export const feature={home:'hero-dark','claude-code-usage':'terminal','codex-usage':'pair','claude-usage-limits':'trio','open-source':'code',privacy:'privacy',compare:'compare',download:'onboarding'};
