import {labels,base,pathFor} from '../data/shared.mjs';
import {facts} from '../data/facts.mjs';
export function GET(){
  return new Response(['# AI Usage Menu',...Object.entries(facts).map(([k,v])=>k+': '+v),'',...Object.entries(labels).map(([id,label])=>label+': '+base+pathFor(id)),'Full text: '+base+'/llms-full.txt'].join('\n'));
}
