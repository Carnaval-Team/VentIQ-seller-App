# Instrumented DOM probe: runs the REAL page in headless Chrome and dumps measurements as JSON.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File __agent__/landing-verify/probe.ps1 -Label x [-Landing path] [-Scheme light|dark|auto]
param(
    [string]$Label = "before",
    [string]$Landing = "",
    [string]$Scheme = "light",
    [string]$Only = ""
)

$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($Landing) { $landing = (Resolve-Path $Landing).Path } else { $landing = Join-Path $root "ventiq_landing" }
Write-Host "landing -> $landing"
$probeDir = Join-Path $root "__agent__\landing-verify\probe-$Label"
New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$baseHref = "file:///" + ($landing -replace '\\', '/') + "/"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$schemeFlag = switch ($Scheme) { "light" { "--blink-settings=preferredColorScheme=1" } "dark" { "--blink-settings=preferredColorScheme=2" } default { "" } }

$PRELUDE = @'
function R(el){var r=el.getBoundingClientRect();return {t:Math.round(r.top),l:Math.round(r.left),w:Math.round(r.width),h:Math.round(r.height),b:Math.round(r.bottom)};}
function PUB(obj){var pre=document.getElementById('__probe');if(!pre){pre=document.createElement('pre');pre.id='__probe';
  pre.style.cssText='position:fixed;left:-99999px;top:0;width:1px;height:1px;overflow:hidden;margin:0;padding:0;border:0;';
  document.body.appendChild(pre);}pre.textContent=JSON.stringify(obj);}
function RUN(fn){setTimeout(function(){try{PUB(fn());}catch(e){PUB({error:String(e)});}},700);setTimeout(function(){try{PUB(fn());}catch(e){PUB({error:String(e)});}},2600);}
function ENV(){return {dark:window.matchMedia('(prefers-color-scheme: dark)').matches,w:innerWidth,h:innerHeight,docH:document.documentElement.scrollHeight,bodyBg:getComputedStyle(document.body).backgroundColor,text:getComputedStyle(document.body).color};}
function SETY(y){try{if(window.__v2Lenis&&window.__v2Lenis.scrollTo)window.__v2Lenis.scrollTo(y,{immediate:true,force:true});}catch(e){}window.scrollTo(0,y);}
var CARDS=[].slice.call(document.querySelectorAll('.v2-stack-card'));
function DESCRIBE(label){return {label:label,scrollY:Math.round(window.scrollY),cards:CARDS.map(function(c,i){var s=getComputedStyle(c);
  return {i:i,pos:s.position,top:s.top,op:(+s.opacity).toFixed(2),mb:s.marginBottom,xf:s.transform.slice(0,48),prog:s.getPropertyValue('--stack-progress').trim(),rect:R(c)};})};}
'@

$SCENARIOS = @(
    @{
        Name = "net"; Source = "index.html"; Query = ""; Head = ""; Css = ""
        Java = @'
RUN(function(){var e=ENV();return {env:e,ready:document.readyState,
  geist:document.fonts.check('600 40px Geist'),geistMono:document.fonts.check('400 12px "Geist Mono"'),
  fa:document.fonts.check('900 16px "Font Awesome 6 Free"'),
  gsap:!!window.gsap,scrollTrigger:!!window.ScrollTrigger,lenis:!!window.Lenis,
  inlineTransforms:[].slice.call(document.querySelectorAll('.v2-stack-card')).map(function(c){return c.getAttribute('style');})};});
'@
    }
    @{
        Name = "iframe375"; Source = "IFRAME"; Query = ""; W = 1100; H = 900
        Head = ""
        Css = ""
        Java = @'
function measure(){
  var f=document.getElementById('f'), d=null;
  try{ d=f.contentDocument; }catch(e){ return {error:'cross-origin '+e}; }
  if(!d||!d.documentElement) return {error:'no contentDocument', readyState:(f.contentWindow||{}).document?(f.contentWindow.document.readyState):'?'};
  var w=f.contentWindow, de=d.documentElement;
  var clickables=[].slice.call(d.querySelectorAll('a,button')).map(function(e){var r=e.getBoundingClientRect();
    return {tag:e.tagName,txt:(e.textContent||'').replace(/\s+/g,' ').trim().slice(0,22),w:Math.round(r.width),h:Math.round(r.height),small:(r.height<44||r.width<44)};});
  var texts=[]; ['h1','p.lead','.benefit .d','.foot','.cta','#refCode','#copyBtn'].forEach(function(sel){
    var e=d.querySelector(sel); if(!e)return; var cs=w.getComputedStyle(e); var r=e.getBoundingClientRect();
    texts.push({sel:sel,color:cs.color,fs:cs.fontSize,w:Math.round(r.width),h:Math.round(r.height)});});
  var over=[].slice.call(d.querySelectorAll('*')).filter(function(e){var r=e.getBoundingClientRect();
    return r.width>0 && r.height>0 && (r.right > w.innerWidth+2 || r.left < -2);}).slice(0,6).map(function(e){
    return e.tagName+'.'+String(e.className||'').slice(0,18)+' right='+Math.round(e.getBoundingClientRect().right);});
  return {iframeCss:f.clientWidth+'x'+f.clientHeight, innerViewport:w.innerWidth+'x'+w.innerHeight,
    docScrollW:de.scrollWidth, hOverflow:de.scrollWidth>w.innerWidth+1, docH:de.scrollHeight,
    overflowingElements:over, clickables:clickables, texts:texts};
}
function tryPub(tag){ try{ var r=measure(); r.at=tag; PUB(r); }catch(e){ PUB({at:tag,scenarioError:String(e)}); } }
tryPub('sync');
(function(){ var f=document.getElementById('f'); if(f){ f.addEventListener('load',function(){tryPub('iframe-load');}); } })();
setTimeout(function(){tryPub('400ms');},400);
setTimeout(function(){tryPub('1600ms');},1600);
setTimeout(function(){tryPub('3800ms');},3800);
'@
    }
    @{
        Name = "stackforce"; Source = "index.html"; Query = ""
        Head = @'
<script>
/* Headless+virtual-time produces almost no frames and NO scroll events, so the page's
   scroll -> requestAnimationFrame -> updateStack path can never run. Shim rAF onto
   setTimeout (virtual time DOES advance timers) so the REAL page code executes, then
   dispatch a real scroll event after each scrollTo to reach the same listener. */
(function(){
  var st = window.setTimeout.bind(window);
  window.requestAnimationFrame = function(cb){ return st(function(){ cb(Date.now()); }, 16); };
  window.cancelAnimationFrame = function(id){ clearTimeout(id); };
})();
</script>
'@
        Css = ""
        Java = @'
var SCROLLS=0;
window.addEventListener('scroll',function(){SCROLLS++;},{passive:true});
setTimeout(function(){ PUB({heartbeat:true, note:'script ran', cardCount:CARDS.length, hasLenis:!!window.__v2Lenis}); }, 300);
var tops=CARDS.map(function(c){return Math.round(c.getBoundingClientRect().top+window.scrollY-88);});
var span=(tops[2]||0)-(tops[0]||0);
var stops=[0,0.2,0.4,0.6,0.8,1.0,1.2].map(function(f){return Math.round(tops[0]+span*f);});
var recs=[];var i=0;
function snap(){var o={scrollY:Math.round(window.scrollY),scrollEvents:SCROLLS,ops:[]};
  CARDS.forEach(function(c){var s=getComputedStyle(c);o.ops.push({t:c.getBoundingClientRect().top|0,prog:s.getPropertyValue('--stack-progress').trim(),op:s.opacity,xf:s.transform.slice(0,40)});});
  return o;}
function next(){
  if(i>=stops.length){ PUB({env:ENV(),note:'rAF shimmed to setTimeout; scroll events dispatched synthetically',
    probeTops:tops,span:span,stops:stops,steps:recs}); return; }
  var y=stops[i]; SETY(y);
  try{ window.dispatchEvent(new Event('scroll')); }catch(e){}
  setTimeout(function(){ recs.push(snap()); i++; next(); }, 220);
}
setTimeout(function(){ try{ next(); }catch(e){ PUB({scenarioError:String(e),stack:String(e&&e.stack).slice(0,300)}); } }, 900);
'@
    }
    @{
        Name = "stackdebug2"; Source = "index.html"; Query = ""; Head = ""; Css = ""
        Java = @'
var TICKS=0, SCROLLS=0, HASLENIS=false;
(function(){function l(){TICKS++;requestAnimationFrame(l);}requestAnimationFrame(l);})();
window.addEventListener('scroll',function(){SCROLLS++;},{passive:true});
var tops=CARDS.map(function(c){return Math.round(c.getBoundingClientRect().top+window.scrollY-88);});
var span=(tops[2]||0)-(tops[0]||0);
var stops=[0,0.2,0.4,0.6,0.8,1.0,1.2].map(function(f){return Math.round(tops[0]+span*f);});
var recs=[];var i=0;
function snap(){var o={scrollY:Math.round(window.scrollY),ticks:TICKS,scrolls:SCROLLS,ops:[]};
  CARDS.forEach(function(c){var s=getComputedStyle(c);o.ops.push({t:c.getBoundingClientRect().top|0,prog:s.getPropertyValue('--stack-progress').trim(),op:s.opacity,xf:s.transform.slice(0,34)});});
  return o;}
function next(){
  if(i>=stops.length){
    var before=snap();
    try{window.dispatchEvent(new Event('scroll'));}catch(e){}
    setTimeout(function(){var after=snap();
      var changed=false;for(var k=0;k<after.ops.length;k++){if(after.ops[k].prog!==before.ops[k].prog)changed=true;}
      PUB({env:ENV(),hasLenis:HASLENIS,probeTops:tops,span:span,stops:stops,
        note:'probeTops computed at scroll 0 via rect; expected p = clamp01((scrollY+88-top_i)/(top_i+1 - top_i))',
        syntheticScrollChangedProgress:changed,beforeSynthetic:before,afterSynthetic:after,steps:recs});},400);
    return;}
  var y=stops[i]; SETY(y);
  setTimeout(function(){recs.push(snap());i++;next();},320);
}
setTimeout(function(){ HASLENIS=!!window.__v2Lenis; next(); },2300);
'@
    }
    @{
        Name = "walk"; Source = "index.html"; Query = ""; Head = ""; Css = ""
        Java = @'
var tops=CARDS.map(function(c){return Math.round(c.getBoundingClientRect().top+window.scrollY-88);});
var span=(tops[2]||0)-(tops[0]||0);
var targets=[0,0.15,0.3,0.45,0.6,0.75,0.9,1.05,1.2,1.4].map(function(f){return Math.round(tops[0]+span*f);});
var recs=[];var i=0;
function next(){ if(i>=targets.length){PUB({env:ENV(),tops:tops,steps:recs});return;} var y=targets[i]; SETY(y);
  setTimeout(function(){ recs.push(DESCRIBE('stop'+i+'_want'+y)); i++; next(); },220); }
setTimeout(next,500);
'@
    }
    @{
        Name = "text"; Source = "index.html"; Query = ""; Head = ""; Css = ""
        Java = @'
RUN(function(){
  var out=ENV(); out.ems=[]; out.words=[]; out.num=[];
  [].slice.call(document.querySelectorAll('h1 em, h2 em, h3 em, .v2-h em, .v2-cta h2 em')).forEach(function(el){
    var cs=getComputedStyle(el);
    out.ems.push({text:el.textContent.trim(),padL:cs.paddingLeft,padR:cs.paddingRight,marginL:cs.marginLeft,marginR:cs.marginRight,
      fontStyle:cs.fontStyle,letterSpacing:cs.letterSpacing,lineHeight:cs.lineHeight,display:cs.display,overflow:cs.overflow,
      clip:cs.webkitBackgroundClip||cs.backgroundClip,fill:cs.webkitTextFillColor||cs.color,
      scrollW:el.scrollWidth,clientW:el.clientWidth,rect:R(el)});
  });
  [].slice.call(document.querySelectorAll('.v2-hero h1 .word')).forEach(function(el){
    out.words.push({text:el.textContent,overflow:getComputedStyle(el).overflow,scrollH:el.scrollHeight,clientH:el.clientHeight,
      clippedH:el.scrollHeight>el.clientHeight+1,innerXf:getComputedStyle(el.firstChild||el).transform.slice(0,40)});
  });
  [].slice.call(document.querySelectorAll('.v2-tile-stat .v2-num')).forEach(function(el){
    var cs=getComputedStyle(el);
    out.num.push({text:el.textContent,padL:cs.paddingLeft,padR:cs.paddingRight,clip:cs.webkitBackgroundClip||cs.backgroundClip,fill:cs.webkitTextFillColor,scrollW:el.scrollWidth,clientW:el.clientWidth,rect:R(el)});
  });
  return out;});
'@
    }
    @{
        Name = "cta"; Source = "index.html"; Query = ""; Head = ""; Css = ""
        Java = @'
RUN(function(){
  var out=ENV(); out.btns=[]; 
  [].slice.call(document.querySelectorAll('.v2-btn,.v2-nav-cta')).forEach(function(el){
    var cs=getComputedStyle(el);
    out.btns.push({text:el.textContent.replace(/\s+/g,' ').trim().slice(0,34),
      where:(el.closest('header')?'hero':(el.closest('footer')?'footer':(el.closest('.v2-drawer')?'drawer':(el.closest('section')?('#'+el.closest('section').id):'?')))),
      cls:el.className,color:cs.color,colorInheritedFrom:(function(){var p=el.parentElement;while(p){var c=getComputedStyle(p).color;if(c!=='rgba(0, 0, 0, 0)')return p.tagName+'.'+(p.className||'').slice(0,24)+':'+c;p=p.parentElement;}return null;})(),
      bg:cs.backgroundImage.slice(0,110),rect:R(el)});
  });
  out.tags=[]; [].slice.call(document.querySelectorAll('.v2-stack-tag')).forEach(function(el){out.tags.push({text:el.textContent.trim(),color:getComputedStyle(el).color});});
  out.mute=[]; [].slice.call(document.querySelectorAll('.v2-footer-bottom,.v2-footer ul a')).forEach(function(el){out.mute.push({t:el.tagName,color:getComputedStyle(el).color});});
  out.pulse=[]; [].slice.call(document.querySelectorAll('.v2-eyebrow-pulse')).forEach(function(el){out.pulse.push({bg:getComputedStyle(el).backgroundColor,shadow:getComputedStyle(el).boxShadow.slice(0,60)});});
  out.tile1=(function(){var t=document.querySelector('.v2-tile-1');return t?getComputedStyle(t).backgroundImage.slice(0,200):null;})();
  return out;});
'@
    }
    @{
        Name = "inkmetrics"; Source = "index.html"; Query = ""; Head = ""; Css = ""
        Java = @'
RUN(function(){
  var c=document.createElement('canvas').getContext('2d');
  var out={env:ENV(),italicGeist:document.fonts.check('italic 600 86px Geist'),
           geist600:document.fonts.check('600 86px Geist'),items:[]};
  [].slice.call(document.querySelectorAll('h1 em, h2 em, .v2-h em, .v2-cta h2 em, .v2-num, .v2-hero h1 .word')).forEach(function(el){
    var cs=getComputedStyle(el);
    c.font=cs.fontStyle+' '+cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;
    try{ c.letterSpacing = (cs.letterSpacing==='normal'?'0px':cs.letterSpacing); }catch(e){}
    var m=c.measureText(el.textContent);
    var padL=parseFloat(cs.paddingLeft)||0, padR=parseFloat(cs.paddingRight)||0;
    var boxW=el.clientWidth, contentW=boxW-padL-padR;
    var inkL=m.actualBoundingBoxLeft, inkR=m.actualBoundingBoxRight;
    out.items.push({text:el.textContent.trim().slice(0,16),cls:String(el.className||'').slice(0,24),
      fs:cs.fontSize,ls:cs.letterSpacing,fstyle:cs.fontStyle,padL:padL,padR:padR,
      contentW:+contentW.toFixed(2),inkL:+inkL.toFixed(2),inkR:+inkR.toFixed(2),
      deficitL:+(inkL-padL).toFixed(2), deficitR:+(inkR-(contentW+padR)).toFixed(2),
      clip:cs.webkitBackgroundClip||cs.backgroundClip, fill:(cs.webkitTextFillColor||cs.color)});
  });
  return out;});
'@
    }
    @{
        Name = "clipboard-notrack"; Source = "r.html"; Query = "?code=ABC123"
        Strip = @('<script src="assets/js/supabase.min.js"></script>', '<script src="assets/js/tracking.js"></script>')
        Head = @'
<script>
window.__copyLog=[];
(function(){
  var fake={writeText:function(t){window.__copyLog.push({via:'writeText',payload:String(t)});return Promise.resolve();}};
  try{ Object.defineProperty(navigator,'clipboard',{value:fake,configurable:true}); }catch(e){ try{navigator.clipboard=fake;}catch(e2){} }
  window.addEventListener('error',function(ev){window.__copyLog.push({via:'windowError',msg:String(ev.message).slice(0,160)});});
})();
</script>
'@
        Css = ""
        Java = @'
setTimeout(function(){
  var b=document.getElementById('ctaBtn'); if(b){ try{b.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}));}catch(e){} }
  setTimeout(function(){
    PUB({scenario:'clipboard-notrack',note:'tracking.js + supabase.min.js script tags REMOVED from the DOM',
      log:window.__copyLog.slice(),
      trackingGlobal:typeof window.VentiqTracking,
      bodyCopyBtnText:(function(){var b=document.querySelector('#copyBtn,#chipCopy,[data-copy]');return b?b.textContent.replace(/\s+/g,' ').trim().slice(0,24):null;})(),
      manualShown:(function(){var m=document.getElementById('manualCopy');return m?getComputedStyle(m).display!=='none':null;})(),
      codeText:(function(){var c=document.getElementById('refCode');return c?c.textContent.trim():null;})(),
      errorsCount:window.__copyLog.filter(function(e){return e.via==='windowError';}).length});
  },800);
},1400);
'@
    }
    @{
        Name = "clipboard-alldead"; Source = "r.html"; Query = "?code=ABC123"
        Strip = @('<script src="assets/js/supabase.min.js"></script>', '<script src="assets/js/tracking.js"></script>')
        Head = @'
<script>
window.__copyLog=[];window.__writeRejects=true;window.__execFails=true;
(function(){
  var fake={writeText:function(t){window.__copyLog.push({via:'writeText',payload:String(t)});return Promise.reject(new Error('notallowed'));}};
  try{ Object.defineProperty(navigator,'clipboard',{value:fake,configurable:true}); }catch(e){ try{navigator.clipboard=fake;}catch(e2){} }
  document.execCommand=function(cmd){ if(cmd==='copy'){ window.__copyLog.push({via:'execCommand',sel:String(window.getSelection?window.getSelection().toString():'').slice(0,80)}); return false;} return false; };
  window.addEventListener('error',function(ev){window.__copyLog.push({via:'windowError',msg:String(ev.message).slice(0,160)});});
})();
</script>
'@
        Css = ""
        Java = @'
setTimeout(function(){
  var b=document.getElementById('ctaBtn'); if(b){ try{b.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}));}catch(e){} }
  setTimeout(function(){
    PUB({scenario:'clipboard-alldead',note:'no tracking, writeText rejects, execCommand false',
      log:window.__copyLog.slice(),
      copyBtnText:(function(){var b=document.querySelector('#copyBtn,#chipCopy,[data-copy]');return b?b.textContent.replace(/\s+/g,' ').trim().slice(0,24):null;})(),
      manualShown:(function(){var m=document.getElementById('manualCopy');return m?getComputedStyle(m).display!=='none':null;})(),
      hintText:(function(){var h=document.getElementById('ctaHint');return h?h.textContent.replace(/\s+/g,' ').trim().slice(0,60):null;})(),
      visibleSelection:String(window.getSelection?window.getSelection().toString():'').slice(0,40),
      errorsCount:window.__copyLog.filter(function(e){return e.via==='windowError';}).length});
  },900);
},1400);
'@
    }
    @{
        Name = "rlayout"; Source = "r.html"; Query = "?code=ABC123"; W = 750; H = 1624; Dsf = 2
        Strip = @('<script src="assets/js/supabase.min.js"></script>', '<script src="assets/js/tracking.js"></script>')
        Head = "<script>try{localStorage.clear();sessionStorage.clear();}catch(e){}</script>"
        Css = ""
        Java = @'
RUN(function(){
  var de=document.documentElement;
  var out={env:ENV(),docScrollW:de.scrollWidth,hOverflow:de.scrollWidth>innerWidth+1,
    themeColors:[].slice.call(document.querySelectorAll('meta[name=theme-color]')).map(function(m){return m.getAttribute('media')+'='+m.content;}),
    clickables:[],texts:[]};
  [].slice.call(document.querySelectorAll('a,button')).forEach(function(e){var r=e.getBoundingClientRect();
    if(r.width<1&&r.height<1)return;
    out.clickables.push({tag:e.tagName,txt:(e.textContent||'').replace(/\s+/g,' ').trim().slice(0,24),w:Math.round(r.width),h:Math.round(r.height),tooSmall:(r.height<44||r.width<44)});});
  ['h1','p.lead','.benefit .d','.foot','.cta','.chip','footer a','#refCode'].forEach(function(sel){
    var e=document.querySelector(sel); if(!e)return; var cs=getComputedStyle(e);
    out.texts.push({sel:sel,txt:(e.textContent||'').replace(/\s+/g,' ').trim().slice(0,30),color:cs.color,fs:cs.fontSize,rect:R(e)});});
  return out;});
'@
    }
    @{
        Name = "rlayout-desktop"; Source = "r.html"; Query = "?code=ABC123"; W = 1440; H = 900
        Strip = @('<script src="assets/js/supabase.min.js"></script>', '<script src="assets/js/tracking.js"></script>')
        Head = "<script>try{localStorage.clear();sessionStorage.clear();}catch(e){}</script>"
        Css = ""
        Java = @'
RUN(function(){
  var de=document.documentElement;
  var out={env:ENV(),docScrollW:de.scrollWidth,hOverflow:de.scrollWidth>innerWidth+1,
    wrapW:Math.round((document.querySelector('.wrap')||document.body).getBoundingClientRect().width),
    chip:(function(){var e=document.getElementById('refChip');return e?getComputedStyle(e).display:null;})(),
    copyBtn:(function(){var b=document.querySelector('#copyBtn,#chipCopy,[data-copy]');if(!b)return null;var r=b.getBoundingClientRect();return {txt:b.textContent.replace(/\s+/g,' ').trim().slice(0,24),w:Math.round(r.width),h:Math.round(r.height)};})()};
  return out;});
'@
    }
    @{
        Name = "raster"; Source = "index.html"; Query = ""; Head = ""; Css = ""
        Java = @'
RUN(function(){
  var W=1500,H=360,BASE=260;
  function inkData(font,ch,ox){
    var cv=document.createElement('canvas');cv.width=W;cv.height=H;
    var x=cv.getContext('2d');x.font=font;x.textBaseline='alphabetic';x.fillStyle='#000';
    x.fillText(ch,ox,BASE);
    return x.getImageData(0,0,W,H).data;
  }
  function analyze(el){
    var cs=getComputedStyle(el);
    var font=cs.fontStyle+' '+cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;
    var c=document.createElement('canvas').getContext('2d');
    c.letterSpacing='0px'; c.font=font;
    var ls=parseFloat(cs.letterSpacing)||0, t=el.textContent, ox=60, gl=[];
    for(var i=0;i<t.length;i++){ var m=c.measureText(t[i]); gl.push({ch:t[i],ox:ox}); ox+=m.width+ls; }
    var masks=gl.map(function(g){return inkData(font,g.ch,g.ox);});
    var pairs=[], worst=0;
    for(var i=0;i+1<masks.length;i++){
      var A=masks[i],B=masks[i+1],shared=0,minx=1e9,maxx=-1;
      for(var p=0;p<A.length;p+=4){
        if(A[p+3]>128 && B[p+3]>128){ shared++; var px=(p>>2)%W; if(px<minx)minx=px; if(px>maxx)maxx=px; }
      }
      if(shared>0){ var wpx=maxx-minx+1; if(wpx>worst)worst=wpx;
        pairs.push({pair:gl[i].ch+gl[i+1].ch,sharedPixels:shared,widthPx:wpx}); }
    }
    return {text:t,fs:cs.fontSize,ls:cs.letterSpacing,style:cs.fontStyle,collidingPairs:pairs,worstOverlapPx:worst};
  }
  var out={env:ENV(),note:'per-glyph rasterised ink overlap: >0 shared pixels means the two glyphs ink physically intersect',items:[]};
  [].slice.call(document.querySelectorAll('.v2-hero h1 em, .v2-h em, .v2-cta h2 em')).forEach(function(el){out.items.push(analyze(el));});
  return out;});
'@
    }
    @{
        Name = "glyphs"; Source = "index.html"; Query = ""; Head = ""; Css = ""
        Java = @'
RUN(function(){
  var c=document.createElement('canvas').getContext('2d');
  function analyze(el){
    var cs=getComputedStyle(el);
    c.letterSpacing='0px';
    c.font=cs.fontStyle+' '+cs.fontWeight+' '+cs.fontSize+' '+cs.fontFamily;
    var ls=parseFloat(cs.letterSpacing)||0, t=el.textContent, x=0, g=[];
    for(var i=0;i<t.length;i++){
      var m=c.measureText(t[i]);
      g.push({ch:t[i],x:+x.toFixed(2),adv:+m.width.toFixed(2),inkL:+m.actualBoundingBoxLeft.toFixed(2),inkR:+m.actualBoundingBoxRight.toFixed(2)});
      x+=m.width+ls;
    }
    var coll=[];
    for(var j=0;j+1<g.length;j++){
      var a=g[j],b=g[j+1];
      var overlap=(a.x+a.inkR)-(b.x-b.inkL);
      if(overlap>0.4) coll.push({pair:a.ch+b.ch,overlap:+overlap.toFixed(2)});
    }
    return {text:t,fs:cs.fontSize,style:cs.fontStyle,ls:cs.letterSpacing,advanceTotal:+x.toFixed(2),collisions:coll};
  }
  var out={env:ENV(),items:[]};
  [].slice.call(document.querySelectorAll('.v2-hero h1 em, .v2-h em, .v2-cta h2 em')).forEach(function(el){ out.items.push(analyze(el)); });
  return out;});
'@
    }
    @{
        Name = "clipboard-nocode"; Source = "r.html"; Query = ""
        Strip = @('<script src="assets/js/supabase.min.js"></script>', '<script src="assets/js/tracking.js"></script>')
        Head = @'
<script>
window.__copyLog=[];
try{ localStorage.clear(); sessionStorage.clear(); }catch(e){}
(function(){
  var fake={writeText:function(t){window.__copyLog.push({via:'writeText',payload:String(t)});return Promise.resolve();}};
  try{ Object.defineProperty(navigator,'clipboard',{value:fake,configurable:true}); }catch(e){ try{navigator.clipboard=fake;}catch(e2){} }
  document.execCommand=function(cmd){ if(cmd==='copy'){window.__copyLog.push({via:'execCommand'});return true;} return false; };
  window.addEventListener('error',function(ev){window.__copyLog.push({via:'windowError',msg:String(ev.message).slice(0,160)});});
})();
</script>
'@
        Css = ""
        Java = @'
setTimeout(function(){
  var b=document.getElementById('ctaBtn'); if(b){ try{b.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}));}catch(e){} }
  setTimeout(function(){
    PUB({scenario:'clipboard-nocode',note:'no query, storage cleared, no tracking -> must copy NOTHING',
      log:window.__copyLog.slice(),
      chipShown:(function(){var c=document.getElementById('refChip');return c?getComputedStyle(c).display!=='none':null;})(),
      codeText:(function(){var c=document.getElementById('refCode');return c?c.textContent.trim():null;})(),
      copyBtnText:(function(){var b=document.querySelector('#copyBtn,#chipCopy,[data-copy]');return b?b.textContent.replace(/\s+/g,' ').trim().slice(0,24):null;})(),
      errorsCount:window.__copyLog.filter(function(e){return e.via==='windowError';}).length});
  },900);
},1400);
'@
    }
    @{
        Name = "clipboard"; Source = "r.html"; Query = "?code=ABC123"; Head = @'
<script>
window.__copyLog=[];
(function(){
  var fake={writeText:function(t){window.__copyLog.push({via:'writeText',payload:String(t),at:Date.now()});return window.__writeRejects?Promise.reject(new Error('denied')):Promise.resolve();}};
  try{ Object.defineProperty(navigator,'clipboard',{value:fake,configurable:true}); }catch(e){ try{navigator.clipboard=fake;}catch(e2){} }
  var realExec=document.execCommand?document.execCommand.bind(document):null;
  document.execCommand=function(cmd){ if(cmd==='copy'){ window.__copyLog.push({via:'execCommand',sel:String(window.getSelection?window.getSelection().toString():'').slice(0,80),at:Date.now()}); return window.__execFails?false:true;} return realExec?realExec.apply(null,arguments):false; };
  window.addEventListener('error',function(ev){window.__copyLog.push({via:'windowError',msg:String(ev.message).slice(0,140)});});
})();
</script>
'@
        Css = ""
        Java = @'
function snap(phase){return {phase:phase,log:window.__copyLog.slice(),
  manualShown:(function(){var m=document.getElementById('manualCopy');return m?getComputedStyle(m).display!=='none':null;})(),
  chipShown:(function(){var c=document.getElementById('refChip');return c?getComputedStyle(c).display!=='none':null;})(),
  codeText:(function(){var c=document.getElementById('refCode');return c?c.textContent.trim():null;})(),
  copyBtn:(function(){var b=document.getElementById('copyBtn')||document.querySelector('[data-copy],.copy-btn,#chipCopy');return b?{text:b.textContent.replace(/\s+/g,' ').trim().slice(0,30),rect:R(b)}:null;})(),
  toast:(function(){var t=document.getElementById('toastText');return t?t.textContent.trim():null;})(),
  tracking:!!window.VentiqTracking,manualVal:(function(){var t=document.getElementById('manualCopyText');return t?t.value:null;})()};}
var S1=snap('load');
setTimeout(function(){
  var b=document.getElementById('ctaBtn');
  if(b){ try{b.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}));}catch(e){b.dispatchEvent(new MouseEvent('pointerdown',{bubbles:true}));} }
  setTimeout(function(){ PUB({scenario:'clipboard',load:S1,afterGesture:snap('gesture')}); },600);
},1600);
'@
    }
    @{
        Name = "clipboard-nojs"; Source = "r.html"; Query = "?code=ABC123"; Head = @'
<script src="assets/js/__missing_tracking.js"></script>
<script>
window.__copyLog=[];
(function(){
  var fake={writeText:function(t){window.__copyLog.push({via:'writeText',payload:String(t)});return Promise.reject(new Error('denied'));}};
  try{ Object.defineProperty(navigator,'clipboard',{value:fake,configurable:true}); }catch(e){ try{navigator.clipboard=fake;}catch(e2){} }
  document.execCommand=function(cmd){ if(cmd==='copy'){ window.__copyLog.push({via:'execCommand',sel:String(window.getSelection?window.getSelection().toString():'').slice(0,80)}); return true;} return false; };
  window.addEventListener('error',function(ev){window.__copyLog.push({via:'windowError',msg:String(ev.message).slice(0,140)});});
})();
</script>
'@
        Css = ""
        Java = @'
setTimeout(function(){
  var m=document.getElementById('manualCopy');
  PUB({scenario:'clipboard-nojs',note:'writeText rejects, execCommand ok, tracking.js missing',
    log:window.__copyLog.slice(),
    manualShown:m?getComputedStyle(m).display!=='none':null,
    chipShown:(function(){var c=document.getElementById('refChip');return c?getComputedStyle(c).display!=='none':null;})(),
    codeText:(function(){var c=document.getElementById('refCode');return c?c.textContent.trim():null;})(),
    tracking:!!window.VentiqTracking,errors:window.__copyLog.filter(function(e){return e.via==='windowError';}).length});
},2400);
'@
    }
)

foreach ($s in $SCENARIOS) {
    if ($Only -and $s.Name -notlike "*$Only*") { continue }
    $src = Join-Path $landing $s.Source
    if ($s.Source -eq 'IFRAME') {
        $html = '<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><base href="' + $baseHref + '">' +
                '<style>html,body{margin:0;padding:0}iframe{width:375px;height:812px;border:0;display:block}</style></head>' +
                '<body><iframe id="f" src="r.html?code=ABC123"></iframe><script>' + $PRELUDE + "`n" + $s.Java + '</script></body></html>'
        $probeFile = Join-Path $probeDir ("probe-" + $s.Name + ".html")
        [System.IO.File]::WriteAllText($probeFile, $html, $utf8)
        $url = "file:///" + ($probeFile -replace '\\', '/')
        $args = @("--headless=new","--disable-gpu","--no-sandbox","--hide-scrollbars","--allow-file-access-from-files",
                  "--virtual-time-budget=20000","--window-size=$($s.W),$($s.H)","--dump-dom")
        $args += $url
        $dom = & $chrome @args 2>$null | Out-String
        [System.IO.File]::WriteAllText((Join-Path $probeDir ($s.Name + '.dom.html')), $dom, $utf8)
        $m = [regex]::Match($dom, '(?s)<pre id="__probe"[^>]*>(.*?)</pre>')
        Write-Host ("=== " + $s.Name + " (" + $Scheme + ") ===")
        if ($m.Success) { Write-Host ([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) } else { Write-Host "(no payload) domLen=$($dom.Length)" }
        Write-Host ""
        continue
    }
    $html = Get-Content -Raw -LiteralPath $src
    if ($s.ContainsKey('Strip')) { foreach ($rx in $s.Strip) { $html = $html -replace [regex]::Escape($rx), '' } }
    $head = '<base href="' + $baseHref + '">' + $s.Head
    if ($s.Css) { $head += "<style>$($s.Css)</style>" }
    $html = $html -replace '(?i)(<head[^>]*>)', ('$1' + "`n" + $head)
    $body = "<script>`n" + $PRELUDE + "`n" + $s.Java + "`n</script>"
    $html = $html -replace '(?i)(</body>)', ($body + "`n" + '$1')
    $probeFile = Join-Path $probeDir ("probe-" + $s.Name + ".html")
    [System.IO.File]::WriteAllText($probeFile, $html, $utf8)

    $url = "file:///" + ($probeFile -replace '\\', '/') + $s.Query
    $winW = if ($s.ContainsKey('W')) { $s.W } else { 1440 }
    $winH = if ($s.ContainsKey('H')) { $s.H } else { 900 }
    $args = @("--headless=new","--disable-gpu","--no-sandbox","--hide-scrollbars","--virtual-time-budget=9000","--window-size=$winW,$winH","--dump-dom")
    # DSF lets us reach a true 375 CSS px viewport (Chrome clamps window width ~500px):
    # --window-size=750,1624 --force-device-scale-factor=2 == 375x812 CSS px.
    $dsf = if ($s.ContainsKey('Dsf')) { $s.Dsf } else { 1 }
    if ($dsf -ne 1) { $args += "--force-device-scale-factor=$dsf" }
    # A screenshot forces the compositor to produce frames, otherwise requestAnimationFrame
    # barely fires in headless and any rAF-driven animation looks frozen.
    $args += "--screenshot=" + (Join-Path $probeDir ("frame-" + $s.Name + ".png"))
    if ($schemeFlag) { $args += $schemeFlag }
    $args += $url
    $dom = & $chrome @args 2>$null | Out-String
    $m = [regex]::Match($dom, '(?s)<pre id="__probe"[^>]*>(.*?)</pre>')
    Write-Host ("=== " + $s.Name + " (" + $Scheme + ") ===")
    if ($m.Success) { Write-Host ([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) } else { Write-Host "(no payload) domLen=$($dom.Length)" }
    Write-Host ""
}
Write-Host "probe dir -> $probeDir"
