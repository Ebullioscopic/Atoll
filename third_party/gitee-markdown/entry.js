import { marked } from 'marked';
import DOMPurify from 'dompurify';
export function render(source) {
  // Both parsing and sanitization happen in an inert template document.
  // An image must not fetch before the reader's explicit image opt-in gate.
  const template = document.createElement('template');
  const wrapper = document.createElement('div');
  template.content.append(wrapper);
  wrapper.innerHTML = marked.parse(source, {gfm:true, breaks:false});
  DOMPurify.sanitize(wrapper, {
    IN_PLACE:true,
    ALLOWED_TAGS:['div','p','br','hr','h1','h2','h3','h4','h5','h6','a','strong','em','b','i','del','s','blockquote','pre','code','ul','ol','li','table','thead','tbody','tr','th','td','img','details','summary','input','kbd','sup','sub'],
    ALLOWED_ATTR:['href','title','src','alt','colspan','rowspan','align','type','checked','disabled','start'],
    ALLOW_DATA_ATTR:false, ALLOW_ARIA_ATTR:false, RETURN_TRUSTED_TYPE:false
  });
  return wrapper.innerHTML;
}
