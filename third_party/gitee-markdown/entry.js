import { marked } from 'marked';
import DOMPurify from 'dompurify';
export function render(source) {
  return DOMPurify.sanitize(marked.parse(source, {gfm:true, breaks:false}), {
    ALLOWED_TAGS:['p','br','hr','h1','h2','h3','h4','h5','h6','a','strong','em','b','i','del','s','blockquote','pre','code','ul','ol','li','table','thead','tbody','tr','th','td','img','details','summary','input','kbd','sup','sub'],
    ALLOWED_ATTR:['href','title','src','alt','colspan','rowspan','align','type','checked','disabled','start'],
    ALLOW_DATA_ATTR:false, ALLOW_ARIA_ATTR:false, RETURN_TRUSTED_TYPE:false
  });
}
