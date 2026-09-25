/* ═══════════════════════════════════════════════════════════════
   ShipEast Admin Portal — application logic
   Firebase 10.x modular SDK. Styled through SEDS tokens (styles.css).
   ═══════════════════════════════════════════════════════════════ */

import{initializeApp}from'https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js';
import{getAuth,signInWithEmailAndPassword,createUserWithEmailAndPassword,sendPasswordResetEmail,setPersistence,inMemoryPersistence,signOut,onAuthStateChanged,getIdTokenResult,connectAuthEmulator}from'https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js';
import{getFirestore,collection,doc,getDoc,getDocs,addDoc,setDoc,updateDoc,deleteDoc,writeBatch,onSnapshot,query,orderBy,limit,serverTimestamp,runTransaction,Timestamp,connectFirestoreEmulator}from'https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore.js';
import{getStorage,connectStorageEmulator}from'https://www.gstatic.com/firebasejs/10.12.0/firebase-storage.js';
import{getFunctions,httpsCallable,connectFunctionsEmulator}from'https://www.gstatic.com/firebasejs/10.12.0/firebase-functions.js';

// ── Firebase Config ──
// Lives in config.js so the panel can target staging during the Phase 1–3
// migrations (P0-01). config.js also paints a banner on any non-prod
// environment, so it is always visible which database is being mutated.
import{firebaseConfig,USE_EMULATORS,EMULATORS}from'./config.js';
import*as OrderStatus from'./order-status.js';
import{createUploader}from'./image-upload.js';
import{parseBands,formatBands,describeBands,parseAmount}from'./pricing-form.js';
import*as Overseas from'./overseas-status.js';
import*as PromoEligibility from'./promo-eligibility.js';
import{parseLatLng,isValidLatLng,roundCoord,formatLatLng}from'./location-input.js';

const app=initializeApp(firebaseConfig);
const auth=getAuth(app);
const db=getFirestore(app);
const storage=getStorage(app);
const fns=getFunctions(app);

/* ── Local preview only ────────────────────────────────────────────────
   Points every SDK at the emulator suite. Gated on SE_ENV==='local', which
   only resolves for localhost/127.0.0.1, so a deployed panel can never take
   this branch.

   These calls must happen before any read or write. connectFirestoreEmulator
   in particular throws once the instance has been used, which is why this
   sits immediately after the getters rather than inside initApp().

   Note connectFirestoreEmulator hardcodes plain HTTP (no ssl option in the
   10.x SDK), so this only works over a localhost port forward — not over a
   Codespaces *.app.github.dev URL. See tools/dev-up.sh.                  */
if(USE_EMULATORS){
  connectAuthEmulator(auth,'http://localhost:'+EMULATORS.auth,{disableWarnings:true});
  connectFirestoreEmulator(db,'localhost',EMULATORS.firestore);
  connectStorageEmulator(storage,'localhost',EMULATORS.storage);
  connectFunctionsEmulator(fns,'localhost',EMULATORS.functions);
  console.info('[ShipEast Admin] emulator suite: auth/firestore/storage/functions');
}

// ══════════════════════ LOCAL DATA MIRRORS ══════════════════════
var orders=[],drivers=[],merchants=[],promoCodes=[],notifHistory=[],customers=[],inquiries=[];
var analyticsStats={
  'Today':    [{lbl:'Revenue',val:'J$0'},{lbl:'Orders',val:'0'},{lbl:'Customers',val:'0'},{lbl:'Avg Order Value',val:'J$0'}],
  'This Week':[{lbl:'Revenue',val:'J$0'},{lbl:'Orders',val:'0'},{lbl:'Customers',val:'0'},{lbl:'Avg Order Value',val:'J$0'}],
  'This Month':[{lbl:'Revenue',val:'J$0'},{lbl:'Orders',val:'0'},{lbl:'Customers',val:'0'},{lbl:'Avg Order Value',val:'J$0'}],
};
var currentPeriod='Today',ordersFilter='All',driverMode='add',driverEditId=null,merchantMode='add',merchantEditId=null,unsubscribers=[];
// Checklist OR-3 / OR-4 — advanced order filters + sort, applied on top of the
// status tabs and the free-text search.
var ordersAdv={status:'',date:'',merchant:'',driver:'',payment:'',area:'',type:'',sort:'newest'};
var panelMerchantId=null,menuItemsUnsub=null,menuItemEditId=null,panelMenuItems=[],menuItemUploader=null;
var promoEditId=null;  // PR-10: set while the create form is in "edit" mode.
var loadedOnce={orders:false,drivers:false,merchants:false,promos:false,notifs:false,customers:false,overseas:false};
var customerSearch='',panelCustomerId=null;
// The live customers listener mirrors at most this many docs (see startListeners).
var CUSTOMERS_LIMIT=500;
var overseasFilter='open',overseasSearch='',panelInquiryId=null;

// ══════════════════════ PRIMITIVES ══════════════════════
function esc(s){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function $(id){ return document.getElementById(id); }
function reduceMotion(){ return window.matchMedia('(prefers-reduced-motion: reduce)').matches; }

/** Phosphor icon from the inline sprite. */
function icon(name,cls){ return '<svg class="ic '+(cls||'')+'" aria-hidden="true"><use href="#i-'+name+'"/></svg>'; }

/* Money, always tabular. The single place the currency glyph is defined for
   the panel — it must match Money.symbol in both Flutter apps, or the admin
   and the customer read the same order differently. The 'en-JM' locale is kept
   for thousands grouping only; it is not what chooses the symbol. */
function money(n){ return 'J$'+Math.round(Number(n)||0).toLocaleString('en-JM'); }
function parseAmt(a){ var n=parseFloat(String(a==null?'0':a).replace(/[^0-9.]/g,'')); return isNaN(n)?0:n; }
/* DR-25: one Jamaican phone format app-wide — display "1-876-000-0000", dial
   "+18760000000". Mirrors SePhone in both Flutter apps. An unrecognisable
   number is returned trimmed, never mangled. */
function phoneFmt(raw){
  if(raw==null) return '';
  var d=String(raw).replace(/\D/g,'');
  if(d.length===11&&d.charAt(0)==='1') d=d.slice(1);
  if(d.length===10) return '1-'+d.slice(0,3)+'-'+d.slice(3,6)+'-'+d.slice(6);
  if(d.length===7) return '1-876-'+d.slice(0,3)+'-'+d.slice(3);
  return String(raw).trim();
}
function phoneDial(raw){
  if(raw==null||!String(raw).trim()) return '';
  var d=String(raw).replace(/\D/g,'');
  if(d.length===7) d='876'+d;
  if(d.length===10) d='1'+d;
  return d?'+'+d:String(raw).trim();
}
// The customer and driver apps show orders as #ABCD1234 — the first 8
// characters of the Firestore id, upper-cased (order_history_screen.dart:347,
// history_screen.dart:288). The console was printing the full 20-char id, which
// nobody can read out over the phone or match against an app screenshot. Same
// rule here so the id an admin sees is the id the customer sees.
function shortId(id){ var s=String(id||''); return '#'+(s.length>8?s.slice(0,8):s).toUpperCase(); }

// ══════════════════════ STORAGE ══════════════════════
// The panel no longer performs any Cloud Storage operations — photos are stored
// inline in Firestore (this project is not on the Blaze plan). The `storage`
// handle above stays initialised, and the emulator stays wired, only so a future
// return to Storage does not have to reassemble that plumbing. See below.

// ══════════════════════ INLINE IMAGES (no Cloud Storage) ══════════════════════
/* This project is NOT on the Blaze plan, so Cloud Storage is unavailable. Instead
   of uploading photo bytes to a bucket, the compressed image is stored directly
   IN the Firestore document as a base64 `data:` URL. The customer app renders it
   through widgets/app_image.dart (data: → Image.memory, http → network).

   The compressor (image-upload.js) already shrinks a phone photo to modest
   dimensions/quality, so a cover lands around ~40–120 KB — well inside Firestore's
   1 MB-per-document limit. INLINE_MAX_CHARS is a safety net for a pathologically
   busy photo: reject it with a clear message rather than fail the whole save. */
var INLINE_MAX_CHARS=850*1024; // ~850 KB of base64, leaving headroom under 1 MB
function blobToDataUrl(blob){
  return new Promise(function(resolve,reject){
    var r=new FileReader();
    r.onload=function(){ resolve(r.result); };
    r.onerror=function(){ reject(new Error('That image could not be read.')); };
    r.readAsDataURL(blob);
  });
}
/* Drop-in replacement for storageUpload, same (blob,path,onProgress)→Promise<url>
   signature the uploader expects — but the "url" is the image itself. */
function inlineUpload(blob,path,onProgress){
  return blobToDataUrl(blob).then(function(dataUrl){
    if(dataUrl.length>INLINE_MAX_CHARS){
      throw new Error('This photo is too detailed to store — please use a simpler or smaller image.');
    }
    if(onProgress) onProgress(100);
    return dataUrl;
  });
}
/* Nothing to delete: an inline image lives and dies with its document. */
function inlineRemove(){ return Promise.resolve(); }

// ── Toasts (replaces every alert()) ──
var TOAST_ICON={success:'success',error:'error',warning:'warning',info:'info'};
function toast(type,msg,title){
  var host=$('toast-host'); if(!host) return;
  var el=document.createElement('div');
  el.className='toast t-'+type;
  el.setAttribute('role',type==='error'?'alert':'status');
  el.innerHTML=icon(TOAST_ICON[type]||'info')+
    '<div class="toast-msg">'+(title?'<b>'+esc(title)+'</b>':'')+esc(msg)+'</div>';
  host.appendChild(el);
  var life=type==='error'?6000:3600;
  setTimeout(function(){
    el.classList.add('out');
    setTimeout(function(){ el.remove(); },reduceMotion()?0:200);
  },life);
}

// ── Confirm dialog (replaces every confirm()) ──
var confirmResolve=null;
function confirmDialog(opts){
  return new Promise(function(resolve){
    confirmResolve=resolve;
    $('cf-ico').className='m-ico '+(opts.tone||'danger');
    $('cf-ico').innerHTML=icon(opts.tone==='warning'?'warning':'delete','ic-lg');
    $('cf-title').textContent=opts.title||'Are you sure?';
    $('cf-body').textContent=opts.body||'';
    var ok=$('cf-ok');
    ok.textContent=opts.confirmLabel||'Delete';
    ok.className='btn '+(opts.tone==='warning'?'btn-primary':'btn-danger');
    openModal('modal-confirm');
  });
}
function settleConfirm(result){
  closeModal('modal-confirm');
  if(confirmResolve){ var r=confirmResolve; confirmResolve=null; r(result); }
}

// ── Count-up numbers ──
function countUp(el,target,fmt){
  if(!el) return;
  fmt=fmt||function(v){ return String(v); };
  var from=Number(el.dataset.val||0), to=Number(target)||0;
  el.dataset.val=to;
  if(reduceMotion()||from===to){ el.textContent=fmt(to); return; }
  var start=performance.now(),dur=600;
  (function step(now){
    var p=Math.min(1,(now-start)/dur);
    var eased=1-Math.pow(1-p,3);              // decelerate
    el.textContent=fmt(Math.round(from+(to-from)*eased));
    if(p<1) requestAnimationFrame(step);
  })(start);
}

// ── Skeletons ──
function skeletonRows(cols,rows){
  var out='';
  for(var r=0;r<(rows||5);r++){
    out+='<tr class="sk-row">';
    for(var c=0;c<cols;c++){
      var w=c===0?'62%':(c===cols-1?'46px':(38+((c*29)%42))+'%');
      out+='<td><div class="sk sk-line" style="width:'+w+'"></div></td>';
    }
    out+='</tr>';
  }
  return out;
}

// ── Empty-state illustrations (2-tone: coral/red + warm cream) ──
var ART={
  box:'<circle cx="100" cy="104" r="66" fill="#FFF1F3"/>'+
      '<path d="M100 46 40 76v56l60 30 60-30V76z" fill="#F7B9C2"/>'+
      '<path d="M100 46 40 76l60 30 60-30z" fill="#E1495F"/>'+
      '<path d="M100 106v56l60-30V76z" fill="#C8102E"/>'+
      '<path d="M70 61l60 30v22" stroke="#FFF1F3" stroke-width="6" fill="none" stroke-linecap="round"/>',
  search:'<circle cx="100" cy="104" r="66" fill="#FFF1F3"/>'+
      '<circle cx="90" cy="94" r="34" fill="none" stroke="#E1495F" stroke-width="10"/>'+
      '<circle cx="90" cy="94" r="22" fill="#FFE0E5"/>'+
      '<path d="M116 120l26 26" stroke="#C8102E" stroke-width="12" stroke-linecap="round"/>',
  bell:'<circle cx="100" cy="104" r="66" fill="#FFF1F3"/>'+
      '<path d="M100 56a30 30 0 0 1 30 30v26l12 16H58l12-16V86a30 30 0 0 1 30-30z" fill="#E1495F"/>'+
      '<path d="M86 136a14 14 0 0 0 28 0z" fill="#C8102E"/>'+
      '<circle cx="100" cy="50" r="7" fill="#C8102E"/>',
  ticket:'<circle cx="100" cy="104" r="66" fill="#FFF1F3"/>'+
      '<path d="M46 82h108v18a12 12 0 0 0 0 24v18H46v-18a12 12 0 0 0 0-24z" fill="#E1495F"/>'+
      '<path d="M100 82v60" stroke="#FFF1F3" stroke-width="5" stroke-dasharray="8 8"/>'+
      '<circle cx="72" cy="112" r="10" fill="#FFE0E5"/>',
  users:'<circle cx="100" cy="104" r="66" fill="#FFF1F3"/>'+
      '<circle cx="100" cy="88" r="24" fill="#E1495F"/>'+
      '<path d="M56 152a44 44 0 0 1 88 0z" fill="#C8102E"/>',
  store:'<circle cx="100" cy="104" r="66" fill="#FFF1F3"/>'+
      '<path d="M56 88h88v62H56z" fill="#F7B9C2"/>'+
      '<path d="M50 66h100l10 22H40z" fill="#E1495F"/>'+
      '<path d="M86 150v-32h28v32z" fill="#C8102E"/>'
};
function emptyState(art,title,copy,cta){
  return '<div class="empty">'+
    '<svg viewBox="0 0 200 200" aria-hidden="true">'+(ART[art]||ART.box)+'</svg>'+
    '<div class="empty-title">'+esc(title)+'</div>'+
    '<div class="empty-copy">'+esc(copy)+'</div>'+
    (cta||'')+'</div>';
}
function emptyRow(cols,art,title,copy){
  return '<tr><td colspan="'+cols+'">'+emptyState(art,title,copy)+'</td></tr>';
}

// ── Status badges ──
var STATUS_TONE={
  delivered:'success',approved:'success',Active:'success',Online:'success',Open:'success',
  Available:'success',
  pending:'info',Pending:'info','Pending Approval':'info',
  confirmed:'warning',in_transit:'warning',picked_up:'warning',
  'On the Way':'warning','On Delivery':'warning','Picked Up':'warning',
  cancelled:'danger',rejected:'danger',Cancelled:'danger',Closed:'danger',Suspended:'danger',
  Rejected:'danger',
  Expired:'neutral',Offline:'neutral',Inactive:'neutral','Used up':'neutral',
  Scheduled:'info',Paused:'warning',Ended:'neutral'
};
var STATUS_LABEL={in_transit:'In Transit',picked_up:'Picked Up',
  confirmed:'Confirmed',delivered:'Delivered',pending:'Pending',cancelled:'Cancelled',
  approved:'Approved',rejected:'Rejected'};
/* Order type (P5-01). Food is the overwhelming majority and every pre-Phase-5
   order is one, so it gets no badge — a badge on everything is a badge on
   nothing. Only the kinds that need different handling are called out. */
var TYPE_LABEL={package:'Package',overseas:'Overseas'};
function typeBadge(t){
  var lbl=TYPE_LABEL[t]; if(!lbl) return '';
  return ' <span class="bdg bg-info plain" title="Order type">'+esc(lbl)+'</span>';
}
/** Firestore Timestamp → readable local string, or '' when never set. */
/* Accepts a Firestore Timestamp or a plain Date. The order mirror keeps raw
   Timestamps; the overseas mirror converts on the way in, because its list is
   sorted by date rather than by the server. One formatter either way. */
function fmtStamp(ts){
  if(!ts) return '';
  var d=ts.toDate?ts.toDate():(ts instanceof Date?ts:null);
  if(!d) return '';
  if(isNaN(d.getTime())) return '';
  return d.toLocaleString('en-JM',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'});
}
function badge(s){
  return '<span class="bdg bg-'+(STATUS_TONE[s]||'neutral')+'">'+esc(STATUS_LABEL[s]||s)+'</span>';
}

// ── Stars ──
function stars(r){
  var v=Number(r)||0,f=Math.round(v),s='';
  for(var i=1;i<=5;i++) s+=icon(i<=f?'star-f':'star',i<=f?'':'off');
  return '<span class="stars">'+s+'</span><span class="rating-val">'+v.toFixed(1)+'</span>';
}

/* Ratings that nobody has given yet must not render as a score (P3-05).
   The old code defaulted every merchant to 5.0, so the panel showed a perfect
   score for a merchant with zero ratings — a number that looks earned and is
   not. Show the honest empty state instead, exactly as the driver panel
   already does. */
function starsOrNone(rating,count){
  if(!count) return '<span class="cell-mute sm">No ratings yet</span>';
  return stars(rating);
}

/* Same rule for drivers. Their ratingCount is only null on legacy docs written
   before it was recorded, so an existing average is trusted there and only a
   genuinely unrated driver falls through to the empty state. */
function driverStars(d){
  var n=d.ratingTotal!=null?d.ratingTotal:(Number(d.rating)>0?1:0);
  return starsOrNone(d.rating,n);
}

/* Orders placed today for a merchant, derived from the already-loaded orders
   array (SCHEMA.md §d, P3-05). The stored `ordersToday` field had no reset
   mechanism, so it showed 0 for every merchant, permanently.

   Caveat: `orders` holds the 200 most recent. That covers a full day at current
   volume; if daily volume ever approaches 200 this needs a real aggregation
   query rather than an in-memory filter. */
function ordersTodayFor(merchantId){
  var start=new Date(); start.setHours(0,0,0,0);
  return orders.filter(function(o){
    return o.merchantId===merchantId&&o._ts!=null&&o._ts>=start;
  }).length;
}

// ── Category glyphs (duotone tinted chips, per-category hue) ──
var CATS={Food:{ic:'cat-food',cls:'c-food'},Grocery:{ic:'cat-grocery',cls:'c-grocery'},
  Pharmacy:{ic:'cat-pharmacy',cls:'c-pharmacy'},Packages:{ic:'cat-packages',cls:'c-packages'}};
function catIcon(cat,size){
  var c=CATS[cat]||{ic:'merchants',cls:'c-other'};
  return '<div class="cat-ico '+(size==='lg'?'lg ':'')+c.cls+'">'+icon(c.ic)+'</div>';
}
function merchantMedia(m,size){
  if(m.imageUrl) return '<img class="thumb'+(size==='lg'?' lg':'')+'" src="'+esc(m.imageUrl)+'" alt="" '+
    'onerror="this.outerHTML=this.dataset.fb" data-fb="'+esc(catIcon(m.category,size))+'">';
  return catIcon(m.category,size);
}

// ══════════════════════ THEME ══════════════════════
function applyTheme(theme){
  document.documentElement.setAttribute('data-theme',theme);
  var btn=$('theme-btn');
  if(btn){
    btn.innerHTML=icon(theme==='dark'?'sun':'moon');
    btn.setAttribute('aria-label',theme==='dark'?'Switch to light theme':'Switch to dark theme');
    btn.title=btn.getAttribute('aria-label');
  }
}
function initTheme(){
  var saved=null;
  try{ saved=localStorage.getItem('se-theme'); }catch{}
  applyTheme(saved||'light');   // dark ships default-off; toggle lives in the topbar
}
function toggleTheme(){
  var next=document.documentElement.getAttribute('data-theme')==='dark'?'light':'dark';
  applyTheme(next);
  try{ localStorage.setItem('se-theme',next); }catch{}
}

// ══════════════════════ AUTH ══════════════════════
// NOTE: Create admin user in Firebase Console → Authentication → Add user → admin@shipeast.com
function doLogin(){
  var e=$('l-email').value.trim(), p=$('l-pass').value;
  var errEl=$('l-err'), btnEl=$('login-btn');
  errEl.classList.remove('show');
  function fail(msg){
    errEl.innerHTML=icon('warning','ic-sm')+'<span>'+esc(msg)+'</span>';
    errEl.classList.add('show');
    btnEl.disabled=false; btnEl.innerHTML='Sign In'+icon('arrow-right');
  }
  if(!e||!p){ fail('Please enter your email and password.'); return; }
  btnEl.disabled=true; btnEl.innerHTML='<span class="spin"></span>Signing in…';
  signInWithEmailAndPassword(auth,e,p).catch(function(err){
    var bad=['auth/user-not-found','auth/wrong-password','auth/invalid-credential','auth/invalid-email'];
    fail(bad.indexOf(err.code)>-1?'Invalid credentials. Please try again.':err.message);
  });
}
function doLogout(){ signOut(auth); }

/* Password reveal on the login card, matching SeTextField in the customer and
   driver apps. Toggling `type` rather than a CSS trick is what keeps the field
   an autofillable password field for the browser's own manager. */
function togglePassReveal(show){
  var inp=$('l-pass'), btn=$('l-eye');
  if(!inp||!btn) return;
  var reveal=(typeof show==='boolean') ? show : (inp.type==='password');
  inp.type=reveal?'text':'password';
  btn.setAttribute('aria-pressed',reveal?'true':'false');
  btn.setAttribute('aria-label',reveal?'Hide password':'Show password');
  btn.innerHTML=icon(reveal?'view-off':'view');
}

// ══════════════════════ NAVIGATION ══════════════════════
var pageLabels={dashboard:'Dashboard',orders:'Orders',drivers:'Drivers',merchants:'Merchants',
  customers:'Customers',overseas:'Shop & Deliver Requests',notifications:'Notifications',
  promos:'Promo Codes',analytics:'Analytics'};
function navTo(page){
  document.querySelectorAll('.ni').forEach(function(n){ n.classList.remove('active'); });
  var ni=document.querySelector('.ni[data-page="'+page+'"]'); if(ni) ni.classList.add('active');
  document.querySelectorAll('.page').forEach(function(p){ p.classList.remove('active'); });
  var pg=$('page-'+page); if(pg) pg.classList.add('active');
  var lbl=pageLabels[page]||page;
  // The breadcrumb is the topbar's only page label now — the second heading
  // that used to sit under it was the same word again (index.html .tb-bc).
  $('tb-pg').textContent=lbl;
  document.title=lbl+' · ShipEast Admin';
  if(page==='analytics'){ renderBarChart(); }
  // Paints the skeleton if the first snapshot has not landed yet — otherwise
  // an admin who navigates here quickly sees an empty table and reads it as
  // "no customers".
  if(page==='customers'){ renderCustomers(); }
  if(page==='drivers'){ renderDrivers(); }
  if(page==='overseas'){ renderOverseas(); }
  // Loaded on first visit rather than streamed: pricing changes a few times a
  // year, and a live listener would fight the admin's own typing.
  if(page==='settings'&&!pricingLoaded){ loadPricing(); }
  // Landing on a tracked page means the admin has now seen it — clear its dot.
  acknowledgeSection(page);
  if(window.innerWidth<=900) closeMobileSidebar();
}

// ══════════════════════ SIDEBAR ══════════════════════
var sidebarCollapsed=false;
function toggleSidebar(){
  if(window.innerWidth<=900){
    var sb=$('sidebar'), mob=$('mob-overlay');
    if(sb.classList.contains('mob-open')){ sb.classList.remove('mob-open'); mob.classList.remove('open'); }
    else{ sb.classList.remove('collapsed'); sb.classList.add('mob-open'); mob.classList.add('open'); }
  }else{
    sidebarCollapsed=!sidebarCollapsed;
    $('sidebar').classList.toggle('collapsed',sidebarCollapsed);
    $('main').classList.toggle('expanded',sidebarCollapsed);
  }
}
function closeMobileSidebar(){
  $('sidebar').classList.remove('mob-open');
  $('mob-overlay').classList.remove('open');
}

// ══════════════════════ ACTIVITY / UNSEEN TRACKING ══════════════════════
/* A live console shows a new order or overseas enquiry the moment it lands, but
   an admin looking at another page had no way to know anything had happened.
   For each tracked collection we remember which document ids the admin has
   actually seen — persisted in localStorage so a refresh does not re-flag old
   rows — and surface anything new two ways: a coloured count on that section's
   sidebar item, and a matching entry under the topbar bell. Opening the page,
   or "Mark all read", clears it. Colours are the dashboard accents so a red /
   gold / teal / green dot reads the same everywhere. */
var ACT_SECTIONS={
  orders:{one:'order',many:'orders',tone:'brand'},
  overseas:{one:'shop & deliver request',many:'shop & deliver requests',tone:'gold'},
  customers:{one:'customer',many:'customers',tone:'ocean'},
  drivers:{one:'driver',many:'drivers',tone:'success'}
};
var ACT_ORDER=['orders','overseas','customers','drivers'];
var SEEN_KEY='se_seen_v1';
var seenStore={};
try{ seenStore=JSON.parse(localStorage.getItem(SEEN_KEY)||'{}')||{}; }catch{ seenStore={}; }
var unseen={orders:[],overseas:[],customers:[],drivers:[]};
function persistSeen(){ try{ localStorage.setItem(SEEN_KEY,JSON.stringify(seenStore)); }catch{} }
function currentIdsFor(sec){
  var list=sec==='orders'?orders:sec==='overseas'?inquiries:sec==='customers'?customers:sec==='drivers'?drivers:[];
  return list.map(function(x){ return x.id; });
}
function isPageActive(sec){ var p=$('page-'+sec); return !!(p&&p.classList.contains('active')); }
// Recompute a section's unseen set after its snapshot. The first time we ever
// see a section (no stored baseline) we adopt the whole backlog as already-seen
// so a fresh login does not light up every dot with pre-existing rows.
function trackSection(sec){
  var ids=currentIdsFor(sec);
  var exists={}; ids.forEach(function(id){ exists[id]=1; });
  if(!seenStore[sec]){
    seenStore[sec]=ids.slice(); persistSeen(); unseen[sec]=[];
  }else{
    var seen={}; seenStore[sec].forEach(function(id){ seen[id]=1; });
    unseen[sec]=ids.filter(function(id){ return !seen[id]; });
    // Drop ids that no longer exist so the store cannot grow without bound.
    var pruned=seenStore[sec].filter(function(id){ return exists[id]; });
    if(pruned.length!==seenStore[sec].length){ seenStore[sec]=pruned; persistSeen(); }
  }
  // If the admin is already on the page, they are looking at it — clear at once.
  if(isPageActive(sec)&&unseen[sec].length){ seenStore[sec]=ids.slice(); persistSeen(); unseen[sec]=[]; }
  renderActivity();
}
function acknowledgeSection(sec){
  // Only acknowledge once the section has data. Baselining an empty section
  // (navigated to before its first snapshot) would make trackSection later read
  // the whole arriving collection as "new".
  if(!ACT_SECTIONS[sec]||!loadedOnce[sec]) return;
  seenStore[sec]=currentIdsFor(sec); persistSeen(); unseen[sec]=[]; renderActivity();
}
function acknowledgeAll(){ ACT_ORDER.forEach(function(sec){ seenStore[sec]=currentIdsFor(sec); unseen[sec]=[]; }); persistSeen(); renderActivity(); }
function renderActivity(){
  var total=0;
  ACT_ORDER.forEach(function(sec){
    var n=unseen[sec].length; total+=n;
    var ni=document.querySelector('.ni[data-page="'+sec+'"]'); if(!ni) return;
    var b=ni.querySelector('.ni-badge');
    if(n>0){
      if(!b){ b=document.createElement('span'); b.className='ni-badge'; ni.appendChild(b); }
      b.textContent=n>99?'99+':String(n);
      b.setAttribute('data-tone',ACT_SECTIONS[sec].tone);
    }else if(b){ b.remove(); }
  });
  var badge=$('bell-badge');
  if(badge){ if(total>0){ badge.textContent=total>99?'99+':String(total); badge.hidden=false; } else badge.hidden=true; }
  renderBellMenu();
}
function renderBellMenu(){
  var host=$('bell-list'); if(!host) return;
  var items=[];
  ACT_ORDER.forEach(function(sec){
    var n=unseen[sec].length; if(!n) return;
    var s=ACT_SECTIONS[sec];
    items.push('<button class="bell-item" data-bell-page="'+sec+'" role="menuitem">'+
      '<span class="bell-dot" data-tone="'+s.tone+'"></span>'+
      '<span class="bell-txt"><b>'+n+' new '+(n===1?s.one:s.many)+'</b>'+
      '<span class="bell-sub">Tap to review</span></span>'+
      icon('caret-right')+'</button>');
  });
  var clr=$('bell-clear');
  if(!items.length){
    host.innerHTML='<div class="bell-empty">'+icon('check')+'<div>You’re all caught up</div></div>';
    if(clr) clr.hidden=true;
  }else{
    host.innerHTML=items.join('');
    if(clr) clr.hidden=false;
  }
}
function toggleBell(force){
  var menu=$('bell-menu'), btn=$('bell-btn'); if(!menu) return;
  var open=force!=null?force:!menu.classList.contains('open');
  menu.classList.toggle('open',open);
  if(btn) btn.setAttribute('aria-expanded',open?'true':'false');
}

// ══════════════════════ FIRESTORE LISTENERS ══════════════════════
function startListeners(){
  // ORDERS
  try{
    unsubscribers.push(onSnapshot(
      query(collection(db,'orders'),orderBy('createdAt','desc'),limit(200)),
      function(snap){
        orders=snap.docs.map(function(d){
          var o=d.data();
          var ts=o.createdAt&&o.createdAt.toDate?o.createdAt.toDate():null;
          var tsStr=ts?ts.toLocaleTimeString('en-JM',{hour:'2-digit',minute:'2-digit'}):o.time||'—';
          var drvName=o.driverName||o.driver||'';
          if(!drvName&&o.driverId){ var drv=drivers.find(function(x){return x.id===o.driverId;}); if(drv) drvName=drv.name; }
          var rawTotal=o.total!=null?Number(o.total):null;
          return {id:d.id,customer:o.customerName||o.customer||'Unknown',
            // P5-05. The Customers page joins orders to accounts on this, and
            // it was never carried into the mirror because nothing had needed
            // it: the panel only ever showed a denormalised name.
            customerId:o.customerId||'',
            custPhone:o.customerPhone||o.custPhone||'—',
            merchant:o.merchantName||o.merchant||'Unknown',merchantId:o.merchantId||'',merchantAddr:o.merchantAddr||'—',
            driver:drvName||'—',driverId:o.driverId||'',
            driverPhone:o.driverPhone||'—',rawTotal:rawTotal,
            subtotal:o.subtotal!=null?Number(o.subtotal):null,
            orderDeliveryFee:o.deliveryFee!=null?Number(o.deliveryFee):null,
            serviceFee:o.serviceFee!=null?Number(o.serviceFee):null,
            discount:Number(o.discount)||0,promoCode:o.promoCode||null,
            driverCommission:o.driverCommission!=null?Number(o.driverCommission):null,
            amount:rawTotal!=null?money(rawTotal):(o.amount||'—'),
            payment:o.paymentMethod||o.payment||'—',
            status:o.status||'pending',time:tsStr,_ts:ts,items:o.items||[],
            address:o.deliveryAddress||o.address||'—',
            // P5-01. Absent on every order written before Phase 5, and those
            // are all food deliveries — see SCHEMA.md §orders.type.
            type:o.type||'food',pkg:o.package||null,
            /* P5-06. All of the below is already stored on the order and was
               displayed nowhere. deliveryPhotoUrl in particular is proof of
               delivery: the driver photographs the handover, the app uploads
               it, and no human being could see it. A dispute could not be
               settled with evidence the system already had. */
            deliveryPhotoUrl:o.deliveryPhotoUrl||'',
            deliveryNote:o.deliveryNote||'',
            cancelledBy:o.cancelledBy||'',
            cancellationReason:o.cancellationReason||'',
            assignedBy:o.assignedBy||'',
            stamps:{createdAt:o.createdAt,acceptedAt:o.acceptedAt,
              assignedAt:o.assignedAt,pickedUpAt:o.pickedUpAt,
              inTransitAt:o.inTransitAt,deliveredAt:o.deliveredAt,
              cancelledAt:o.cancelledAt,ratedAt:o.ratedAt},
            _docId:d.id};
        });
        loadedOnce.orders=true;
        trackSection('orders');
        syncOrderFilterOptions();
        renderDashboard();renderOrders();renderAnalytics();renderTopMerch();
      },
      function(e){ loadedOnce.orders=true; console.warn('orders:',e.message); toast('error','Could not load orders: '+e.message); renderOrders(); }
    ));
  }catch(e){ console.warn('orders init:',e.message); }

  // DRIVERS
  try{
    unsubscribers.push(onSnapshot(
      collection(db,'drivers'),
      function(snap){
        drivers=snap.docs.map(function(d){
          var o=d.data();
          var rawStatus=o.status||'pending';
          var approved=rawStatus==='approved';
          // DV-2: the state the admin sees is derived — the six the client
          // listed plus Rejected. Presence (online/on delivery/available) only
          // means anything once the account itself is approved.
          var statusLbl;
          if(rawStatus==='suspended') statusLbl='Suspended';
          else if(rawStatus==='paused') statusLbl='Paused';
          else if(rawStatus==='pending') statusLbl='Pending Approval';
          else if(rawStatus==='rejected') statusLbl='Rejected';
          else if(o.onDelivery) statusLbl='On Delivery';
          else if(o.isOnline) statusLbl='Online';
          else statusLbl='Offline';
          var onlineSince=o.onlineSince&&o.onlineSince.toDate?o.onlineSince.toDate():null;
          return {id:d.id,name:o.name||'—',phone:o.phone||'—',email:o.email||'—',
            vtype:o.vehicleType||o.vtype||'Car',vehicle:o.vehicleModel||o.vehicle||'—',
            plate:o.licencePlate||o.plate||'—',dlicence:o.licenceNumber||o.dlicence||'—',
            // Not 5.0. A driver nobody has rated has no score, and defaulting
            // to a perfect one made every freshly added driver look like the
            // best on the roster (same bug as P3-05 on merchants).
            rating:o.averageRating||o.rating||0,trips:o.totalTrips||o.trips||0,
            ratingCounts:o.ratingCounts||o.ratingBreakdown||null,
            ratingTotal:o.ratingCount!=null?o.ratingCount:null,
            avatarUrl:o.avatarUrl||'',onlineSince:onlineSince,
            status:statusLbl,rawStatus:rawStatus,approved:approved,
            // Available = approved, online, and not currently on a delivery.
            available:approved&&o.isOnline&&!o.onDelivery,
            isOnline:o.isOnline||false,onDelivery:o.onDelivery||false,_docId:d.id};
        });
        loadedOnce.drivers=true;
        trackSection('drivers');
        renderDrivers();renderDashboard();renderOrders();
      },
      function(e){ loadedOnce.drivers=true; console.warn('drivers:',e.message); toast('error','Could not load drivers: '+e.message); renderDrivers(); }
    ));
  }catch(e){ console.warn('drivers init:',e.message); }

  // MERCHANTS
  try{
    unsubscribers.push(onSnapshot(
      collection(db,'merchants'),
      function(snap){
        merchants=snap.docs.map(function(d){
          var o=d.data();
          var isOpenVal=o.isOpen!=null?o.isOpen:(o.open!=null?o.open:true);
          // openingHours (business hours) and deliveryTime (ETA) are two
          // different things. They were conflated by the old
          // `o.hours||o.deliveryTime`, which is why every merchant showed the
          // customer app's hardcoded ETA fallback (P3-01).
          return {id:d.id,name:o.name||'—',category:o.category||'Food',owner:o.owner||'—',
            phone:o.phone||'—',email:o.email||'—',address:o.address||'—',
            openingHours:o.openingHours||o.hours||'',
            deliveryTime:o.deliveryTime||'',
            // Legacy `fee` was a display string like '$250'. Read it only as a
            // fallback, and always expose an integer from here on.
            deliveryFee:Math.round(parseAmt(o.deliveryFee!=null?o.deliveryFee:o.fee)),
            rating:o.averageRating||o.rating||0,
            ratingCount:Number(o.ratingCount)||0,
            open:isOpenVal,imageUrl:o.imageUrl||o.image||'',
            // Pickup coordinates (P5-06). Kept as numbers or null so the form
            // and the "has a location" indicator can tell "unset" from "0".
            lat:(o.lat!=null&&isFinite(o.lat))?Number(o.lat):null,
            lng:(o.lng!=null&&isFinite(o.lng))?Number(o.lng):null,
            emoji:o.emoji||'',_docId:d.id};
        });
        loadedOnce.merchants=true;
        renderMerchants();renderTopMerch();
        populateEligPickers(); // PR-5: merchant/category options for the promo form
      },
      function(e){ loadedOnce.merchants=true; console.warn('merchants:',e.message); toast('error','Could not load merchants: '+e.message); renderMerchants(); }
    ));
  }catch(e){ console.warn('merchants init:',e.message); }

  /* CUSTOMERS (P5-05)
     The `users` collection had no admin surface at all. An admin could open an
     order and see a name, and could go no further: no history, no addresses,
     no lifetime value, and no way to stop an account abusing the service.

     The read is permitted by P2-01's `allow read: if uid() == userId ||
     isAdmin()`. There is no orderBy: `createdAt` is absent on every account
     created before Phase 1, and ordering by it would silently hide them.

     Capped at CUSTOMERS_LIMIT. Every other listener here is on a collection that
     stays operationally small (drivers, merchants, promos), but `users` grows
     with the whole customer base, and a live mirror of all of it re-renders on
     any change. The cap keeps the page bounded; renderCustomers shows a notice
     when it is hit, and a server-side customer search is the follow-up for when
     the base outgrows it. */
  try{
    unsubscribers.push(onSnapshot(
      query(collection(db,'users'),limit(CUSTOMERS_LIMIT)),
      function(snap){
        customers=snap.docs.map(function(d){
          var o=d.data();
          var joined=o.createdAt&&o.createdAt.toDate?o.createdAt.toDate():null;
          return {id:d.id,name:o.name||'—',email:o.email||'—',
            phone:o.phone||'—',avatarUrl:o.avatarUrl||'',
            disabled:o.disabled===true,
            disabledReason:o.disabledReason||'',
            // CU-4: operator-assigned segment tags.
            tags:Array.isArray(o.tags)?o.tags:[],
            joined:joined,
            // Presence of a token is the only honest answer available here:
            // whether the device still accepts pushes is known to FCM, not to
            // us, and P4-04 prunes dead ones on the next send.
            hasPush:typeof o.fcmToken==='string'&&o.fcmToken.length>0,
            _docId:d.id};
        });
        loadedOnce.customers=true;
        trackSection('customers');
        renderCustomers();
        populateEligPickers(); // PR-5: "selected customers" options for the promo form
      },
      function(e){ loadedOnce.customers=true; console.warn('users:',e.message); toast('error','Could not load customers: '+e.message); renderCustomers(); }
    ));
  }catch(e){ console.warn('users init:',e.message); }

  /* OVERSEAS ENQUIRIES
     Requests to ship something to family in Jamaica. The customer app used to
     point a WebView at two placeholder form URLs and write nothing anywhere,
     so no request ever reached a person; there was no queue, which is why
     there was no page.

     No orderBy and no limit. `createdAt` is a serverTimestamp, so the newest
     enquiry — the one an operator most needs to see — is briefly null on the
     client, and an orderBy would sort it into the void. Overseas.filterInquiries
     sorts these, and puts the unresolved one first. */
  try{
    unsubscribers.push(onSnapshot(
      collection(db,'overseasInquiries'),
      function(snap){
        inquiries=snap.docs.map(function(d){
          var o=d.data();
          return {id:d.id,
            customerId:o.customerId||'',customerName:o.customerName||'—',
            contactEmail:o.contactEmail||'',contactPhone:o.contactPhone||'',
            originCountry:o.originCountry||'—',
            recipientName:o.recipientName||'—',recipientPhone:o.recipientPhone||'',
            recipientAddress:o.recipientAddress||'—',
            recipientParish:o.recipientParish||'—',
            itemCategory:o.itemCategory||'—',
            itemDescription:o.itemDescription||'—',
            requestedStore:o.requestedStore||'',
            budget:o.budget||'',
            notes:o.notes||'',
            status:Overseas.normalise(o.status),
            adminNote:o.adminNote||'',
            handledBy:o.handledBy||'',handledAt:o.handledAt||null,
            // SD-7 quote sub-fields.
            quoteItemsCost:o.quoteItemsCost!=null?Number(o.quoteItemsCost):null,
            quoteServiceFee:o.quoteServiceFee!=null?Number(o.quoteServiceFee):null,
            quoteDeliveryFee:o.quoteDeliveryFee!=null?Number(o.quoteDeliveryFee):null,
            quoteTotal:o.quoteTotal!=null?Number(o.quoteTotal):null,
            quoteExpiresAt:o.quoteExpiresAt&&o.quoteExpiresAt.toDate?o.quoteExpiresAt.toDate():null,
            quotePaymentStatus:o.quotePaymentStatus||'',
            quotedAt:o.quotedAt&&o.quotedAt.toDate?o.quotedAt.toDate():null,
            createdAt:o.createdAt&&o.createdAt.toDate?o.createdAt.toDate():null,
            updatedAt:o.updatedAt&&o.updatedAt.toDate?o.updatedAt.toDate():null,
            _docId:d.id};
        });
        loadedOnce.overseas=true;
        trackSection('overseas');
        renderOverseas();
      },
      function(e){ loadedOnce.overseas=true; console.warn('overseasInquiries:',e.message); toast('error','Could not load shop & deliver requests: '+e.message); renderOverseas(); }
    ));
  }catch(e){ console.warn('overseasInquiries init:',e.message); }

  // PROMO CODES
  try{
    unsubscribers.push(onSnapshot(
      query(collection(db,'promoCodes'),orderBy('createdAt','desc')),
      function(snap){
        var now=new Date();
        promoCodes=snap.docs.map(function(d){
          var o=d.data();
          // expiresAt is a Timestamp (SCHEMA.md §b). The legacy `validUntil`
          // string is read only so un-migrated codes still display.
          var expiry=o.expiresAt&&o.expiresAt.toDate?o.expiresAt.toDate()
            :(o.validUntil&&o.validUntil!=='—'?new Date(o.validUntil):null);
          if(expiry&&isNaN(expiry.getTime())) expiry=null;
          var expired=expiry!=null&&expiry<=now;
          // PR-6: a code with a future startsAt is live in the collection but
          // not yet redeemable — evaluatePromo rejects it as 'not_yet_started'.
          var startsAt=o.startsAt&&o.startsAt.toDate?o.startsAt.toDate():null;
          if(startsAt&&isNaN(startsAt.getTime())) startsAt=null;
          var scheduled=startsAt!=null&&startsAt>now;
          var usedCount=Number(o.usedCount!=null?o.usedCount:(o.used!=null?o.used:0))||0;
          var maxUses=Number(o.maxUses!=null?o.maxUses:(o.max!=null?o.max:0))||0;
          var exhausted=maxUses>0&&usedCount>=maxUses;
          // PR-10: "Ended" is a deliberate terminal stop (endedAt set), distinct
          // from "Paused" (active:false, resumable) and "Expired" (date passed).
          var ended=!!o.endedAt;
          var paused=o.active===false&&!ended;
          var active=o.active!==false&&!expired&&!exhausted&&!scheduled;
          var discAmt=o.discountAmount!=null?o.discountAmount:(o.discount!=null?o.discount:null);
          var discType=o.discountType==='percentage'?'percent':(o.discountType||o.type||'percent');
          var discStr=discAmt!=null?(discType==='percent'?discAmt+'% Off':money(discAmt)+' Off'):'—';
          var lastRedeemed=o.lastRedeemedAt&&o.lastRedeemedAt.toDate?o.lastRedeemedAt.toDate():null;
          return {id:d.id,code:o.code||d.id,discount:discStr,discountType:discType,discountAmount:discAmt,
            usedCount:usedCount,maxUses:maxUses,
            minOrderTotal:Number(o.minOrderTotal)||0,
            maxDiscount:o.maxDiscount!=null?Number(o.maxDiscount):null,
            expiresAt:expiry,startsAt:startsAt,lastRedeemedAt:lastRedeemed,
            paused:paused,ended:ended,
            // PR-5: who the code is scoped to. Read-only pass-through — the
            // form is the only writer; malformed/legacy values just describe
            // as "open to everyone" (PromoEligibility.describeEligibility).
            eligibility:(o.eligibility&&typeof o.eligibility==='object')?o.eligibility:null,
            // Distinguish the ways a code is not currently redeemable — "Expired"
            // on an exhausted or not-yet-started code sends the admin looking at
            // the wrong field.
            status:ended?'Ended':(paused?'Paused':(active?'Active':(scheduled?'Scheduled':(expired?'Expired':(exhausted?'Used up':'Inactive'))))),
            _docId:d.id};
        });
        loadedOnce.promos=true;
        renderPromos();
      },
      function(e){ loadedOnce.promos=true; console.warn('promoCodes:',e.message); toast('error','Could not load promo codes: '+e.message); renderPromos(); }
    ));
  }catch(e){ console.warn('promoCodes init:',e.message); }

  // NOTIFICATIONS
  try{
    unsubscribers.push(onSnapshot(
      query(collection(db,'notifications'),orderBy('createdAt','desc'),limit(50)),
      function(snap){
        notifHistory=snap.docs.map(function(d){
          var o=d.data();
          var ts=o.createdAt&&o.createdAt.toDate
            ?new Date(o.createdAt.toDate()).toLocaleString('en-JM',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'})
            :'—';
          var TARGETS={customers:'All Customers',drivers:'All Drivers',all:'Everyone'};
          var t=o.target||'all';
          var targetLbl=TARGETS[t]||(t&&t.indexOf('tag:')===0?tagLabel(t.slice(4))+' customers':t);
          var sched=o.scheduledFor&&o.scheduledFor.toDate?o.scheduledFor.toDate():null;
          var dispatched=o.dispatchedAt&&o.dispatchedAt.toDate?o.dispatchedAt.toDate():null;
          return {id:d.id,title:o.title||'—',msg:o.message||'—',target:targetLbl,time:ts,
            sentBy:o.sentBy||null,
            scheduledFor:sched,dispatched:dispatched,
            destType:o.destType||'',destValue:o.destValue||'',
            delivered:typeof o.deliveredCount==='number'?o.deliveredCount:null,
            opened:typeof o.openedCount==='number'?o.openedCount:null,
            failed:typeof o.failedCount==='number'?o.failedCount:null,_docId:d.id};
        });
        loadedOnce.notifs=true;
        renderNotifHist();
      },
      function(e){ loadedOnce.notifs=true; console.warn('notifications:',e.message); renderNotifHist(); }
    ));
  }catch(e){ console.warn('notifications init:',e.message); }
}
function stopListeners(){ unsubscribers.forEach(function(u){ u(); }); unsubscribers=[]; }

// ══════════════════════ SPARKLINE ══════════════════════
function sparkline(values,color){
  if(!values||values.length<2) return '';
  var w=120,h=26,max=Math.max.apply(null,values)||1;
  var pts=values.map(function(v,i){
    return [(i/(values.length-1))*w, h-2-(v/max)*(h-6)];
  });
  var d=pts.map(function(p,i){ return (i?'L':'M')+p[0].toFixed(1)+' '+p[1].toFixed(1); }).join(' ');
  var area=d+' L'+w+' '+h+' L0 '+h+' Z';
  var uid='sp'+Math.random().toString(36).slice(2,8);
  return '<svg class="spark" viewBox="0 0 '+w+' '+h+'" preserveAspectRatio="none" aria-hidden="true">'+
    '<defs><linearGradient id="'+uid+'" x1="0" y1="0" x2="0" y2="1">'+
      '<stop offset="0%" stop-color="'+color+'" stop-opacity=".28"/>'+
      '<stop offset="100%" stop-color="'+color+'" stop-opacity="0"/></linearGradient></defs>'+
    '<path d="'+area+'" fill="url(#'+uid+')"/>'+
    '<path d="'+d+'" fill="none" stroke="'+color+'" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>'+
  '</svg>';
}
function hourlyCounts(list){
  var now=new Date(), out=[];
  for(var h=0;h<24;h+=3){
    var s=new Date(now.getFullYear(),now.getMonth(),now.getDate(),h);
    var e=new Date(s.getTime()+3*3600000);
    out.push(list.filter(function(o){ return o._ts&&o._ts>=s&&o._ts<e; }).length);
  }
  return out;
}

// ══════════════════════ DASHBOARD ══════════════════════
function renderDashboard(){
  var now=new Date();
  var todayStart=new Date(now.getFullYear(),now.getMonth(),now.getDate());
  var todayOrders=orders.filter(function(o){ return o._ts&&o._ts>=todayStart; });
  var deliveredToday=todayOrders.filter(function(o){ return isDeliveredStatus(o.status); });
  var pendingOrders=orders.filter(function(o){ return o.status==='pending'||o.status==='Pending'; }).length;
  var revenueToday=deliveredToday.reduce(function(s,o){ return s+(o.rawTotal!=null?o.rawTotal:parseAmt(o.amount)); },0);
  // DB-3: Online = approved and toggled on; On Delivery = a subset of those
  // currently carrying an order; Available = online and free right now.
  var onlineDrv=drivers.filter(function(d){ return d.isOnline&&d.approved; });
  var onDelivery=onlineDrv.filter(function(d){ return d.onDelivery; }).length;

  countUp($('stat-orders'),todayOrders.length);
  countUp($('stat-revenue'),revenueToday,money);
  countUp($('stat-pending'),pendingOrders);
  countUp($('drv-online'),onlineDrv.length);
  countUp($('drv-ondel'),onDelivery);
  countUp($('drv-avail'),onlineDrv.length-onDelivery);

  var sp1=$('spark-orders'); if(sp1) sp1.innerHTML=sparkline(hourlyCounts(todayOrders),'#C8102E');
  var sp2=$('spark-revenue'); if(sp2) sp2.innerHTML=sparkline(hourlyCounts(deliveredToday),'#F5A524');

  var tbody=$('dash-tbody');
  if(!loadedOnce.orders){ tbody.innerHTML=skeletonRows(8,5); return; }
  if(!orders.length){
    tbody.innerHTML=emptyRow(8,'box','No orders yet','New customer orders will appear here the moment they are placed.');
    return;
  }
  // DB-9: when the dashboard search has a term, show matches from ALL orders
  // (up to 15); otherwise the ten most recent.
  var dq=(($('dash-search')||{}).value||'').trim().toLowerCase();
  var dqBare=dq.replace(/^#/,'');
  var dashRows=dq
    ? orders.filter(function(o){
        return o.id.toLowerCase().includes(dqBare)||shortId(o.id).toLowerCase().includes(dq)||
          o.customer.toLowerCase().includes(dq)||o.merchant.toLowerCase().includes(dq);
      }).slice(0,15)
    : orders.slice(0,10);
  if(dq&&!dashRows.length){
    tbody.innerHTML=emptyRow(8,'search','No matching orders','Nothing matched “'+esc(dq)+'”. Open the Orders tab for the full history and filters.');
    return;
  }
  tbody.innerHTML=dashRows.map(function(o){
    var dest=(o.address&&o.address!=='—')?o.address:'—';
    // DB-5: recent orders now show the destination and open on a row click.
    return '<tr class="row-click" data-action="view-order" data-oid="'+esc(o._docId||o.id)+'">'+
      '<td><span class="cell-id">'+esc(shortId(o.id))+'</span>'+typeBadge(o.type)+'</td>'+
      '<td>'+esc(o.customer)+'</td>'+
      '<td>'+esc(o.merchant)+'</td>'+
      '<td class="cell-mute cell-clip" title="'+esc(dest)+'">'+esc(dest)+'</td>'+
      '<td class="cell-mute">'+esc(o.driver)+'</td>'+
      '<td class="right cell-strong">'+esc(o.amount)+'</td>'+
      '<td>'+badge(o.status)+'</td>'+
      '<td><button class="aicon ai-v" data-action="view-order" data-oid="'+esc(o._docId||o.id)+'" title="View order" aria-label="View order">'+icon('view')+'</button></td>'+
    '</tr>';
  }).join('');
}

// ══════════════════════ ORDERS ══════════════════════
// Canonical set, plus the display-label variants legacy rows still carry.
function isActiveStatus(s){ return OrderStatus.ACTIVE.indexOf(s)>-1||['Pending','On the Way','Confirmed','Picked Up'].indexOf(s)>-1; }
function isDeliveredStatus(s){ return s==='delivered'||s==='Delivered'; }
function isCancelledStatus(s){ return s==='cancelled'||s==='Cancelled'; }
function updateOrdersTabs(){
  var counts={
    All:orders.length,
    Active:orders.filter(function(o){ return isActiveStatus(o.status); }).length,
    Completed:orders.filter(function(o){ return isDeliveredStatus(o.status); }).length,
    Cancelled:orders.filter(function(o){ return isCancelledStatus(o.status); }).length
  };
  var tabs=$('orders-tabs'); if(!tabs) return;
  tabs.innerHTML=['All','Active','Completed','Cancelled'].map(function(k){
    return '<div class="tab'+(ordersFilter===k?' active':'')+'" data-filter="'+k+'" role="tab" tabindex="0">'+
      k+' <b class="num">'+counts[k]+'</b></div>';
  }).join('');
}
/* OR-3: fills the Merchant / Driver / Payment dropdowns from whatever the loaded
   orders actually reference, so the list never offers a filter that matches
   nothing. Preserves the current selection across refreshes. */
function syncOrderFilterOptions(){
  var defs=[
    ['of-merchant','merchant','Any merchant'],
    ['of-driver','driver','Any driver'],
    ['of-payment','payment','Any payment']
  ];
  defs.forEach(function(d){
    var sel=$(d[0]); if(!sel) return;
    var seen={},vals=[];
    orders.forEach(function(o){
      var v=(o[d[1]]||'').trim();
      if(v&&v!=='—'&&!seen[v]){ seen[v]=1; vals.push(v); }
    });
    vals.sort();
    var cur=sel.value;
    sel.innerHTML='<option value="">'+d[2]+'</option>'+
      vals.map(function(v){ return '<option value="'+esc(v)+'">'+esc(v)+'</option>'; }).join('');
    sel.value=vals.indexOf(cur)>-1?cur:'';
  });
}

/* OR-3: date-range presets. Keeps this out of renderOrders so the boundary
   maths is in one place. */
function orderInDateRange(o,pref){
  if(!pref||!o._ts) return true;
  var now=new Date(), t=o._ts.getTime();
  if(pref==='today'){
    var start=new Date(now.getFullYear(),now.getMonth(),now.getDate()).getTime();
    return t>=start;
  }
  var days=parseInt(pref,10);
  return isFinite(days)?t>=now.getTime()-days*86400000:true;
}

/* OR-3 / OR-4: pull every filter control into `ordersAdv`, mark the ones that
   are set, show the Clear button only when there is something to clear, and
   re-render. One function so the table and the control state cannot drift. */
function readOrderFilters(){
  var map={'of-status':'status','of-date':'date','of-merchant':'merchant',
    'of-driver':'driver','of-payment':'payment','of-area':'area','of-type':'type','of-sort':'sort'};
  var anySet=false;
  Object.keys(map).forEach(function(id){
    var el=$(id); if(!el) return;
    var v=el.value||'';
    ordersAdv[map[id]]=v;
    var isFilter=id!=='of-sort';
    var on=isFilter&&v!=='';
    el.classList.toggle('on',on);
    if(on) anySet=true;
  });
  var clr=$('of-clear'); if(clr) clr.hidden=!anySet;
  renderOrders();
}
function clearOrderFilters(){
  ['of-status','of-date','of-merchant','of-driver','of-payment','of-area','of-type'].forEach(function(id){
    var el=$(id); if(el) el.value='';
  });
  readOrderFilters();
}

function renderOrders(){
  updateOrdersTabs();
  var tbody=$('orders-tbody'); if(!tbody) return;
  if(!loadedOnce.orders){ tbody.innerHTML=skeletonRows(9,7); return; }
  var search=(($('orders-search')||{}).value||'').toLowerCase();
  var f=ordersAdv, area=f.area.toLowerCase();
  var advActive=f.status||f.date||f.merchant||f.driver||f.payment||f.area||f.type;
  var rows=orders.filter(function(o){
    var tm=ordersFilter==='All'||
      (ordersFilter==='Active'&&isActiveStatus(o.status))||
      (ordersFilter==='Completed'&&isDeliveredStatus(o.status))||
      (ordersFilter==='Cancelled'&&isCancelledStatus(o.status));
    // Match the full id (an admin may paste it from the console) and the short
    // #ABCD1234 form the tables now show, with or without the leading '#'.
    var q=search.replace(/^#/,'');
    var sm=!search||o.id.toLowerCase().includes(q)||shortId(o.id).toLowerCase().includes(search)||o.customer.toLowerCase().includes(search)||o.merchant.toLowerCase().includes(search);
    // OR-3 advanced filters.
    var am=(!f.status||o.status===f.status)&&
      orderInDateRange(o,f.date)&&
      (!f.merchant||o.merchant===f.merchant)&&
      (!f.driver||o.driver===f.driver)&&
      (!f.payment||o.payment===f.payment)&&
      (!f.type||o.type===f.type)&&
      (!area||(o.address||'').toLowerCase().includes(area));
    return tm&&sm&&am;
  });
  // OR-4 quick sort. The listener already returns newest-first, so "oldest"
  // is a reverse and "newest" is a no-op — but sort explicitly off _ts so a
  // missing timestamp cannot scramble the order.
  rows.sort(function(a,b){
    var at=a._ts?a._ts.getTime():0, bt=b._ts?b._ts.getTime():0;
    return f.sort==='oldest'?at-bt:bt-at;
  });
  if(!rows.length){
    tbody.innerHTML=(search||advActive)
      ? emptyRow(9,'search','No matching orders','Nothing matched the current search and filters. Clear a filter to widen the list.')
      : emptyRow(9,'box','Nothing in “'+ordersFilter+'”','No orders currently sit in this state.');
    return;
  }
  tbody.innerHTML=rows.map(function(o){
    // DB-5: the whole row opens the order, not just the icon button. The button
    // stays for keyboard users and as an affordance.
    return '<tr class="row-click" data-action="view-order" data-oid="'+esc(o._docId||o.id)+'">'+
      // Beside the id, not in its own column: a package job needs to be
      // obvious at a glance, and the orders table is already nine columns wide.
      '<td><span class="cell-id">'+esc(shortId(o.id))+'</span>'+typeBadge(o.type)+'</td>'+
      '<td>'+esc(o.customer)+'</td>'+
      '<td>'+esc(o.merchant)+'</td>'+
      '<td class="cell-mute">'+esc(o.driver)+'</td>'+
      '<td class="right cell-strong">'+esc(o.amount)+'</td>'+
      '<td><span class="bdg bg-neutral plain">'+esc(o.payment)+'</span></td>'+
      '<td>'+badge(o.status)+'</td>'+
      '<td class="cell-mute num">'+esc(o.time)+'</td>'+
      '<td><button class="aicon ai-v" data-action="view-order" data-oid="'+esc(o._docId||o.id)+'" title="View order" aria-label="View order">'+icon('view')+'</button></td>'+
    '</tr>';
  }).join('');
}

// ══════════════════════ ORDER SIDE PANEL ══════════════════════
/* Flags an order whose parts do not add up (P3-02). Every pre-Phase-3
   discounted order is in this state — the discount was never recorded, so the
   gap between the items and the amount charged is unexplained. Showing it is
   the point: this is the monitoring the plan asks for, in the place an admin
   already looks. */
function reconcileNote(o){
  if(o.rawTotal==null||o.subtotal==null||o.orderDeliveryFee==null||o.serviceFee==null) return '';
  var expected=o.subtotal+o.orderDeliveryFee+o.serviceFee-(o.discount||0);
  if(expected===o.rawTotal) return '';
  return '<div class="sp-row"><span class="sp-lbl">Reconciliation</span>'+
    '<span class="bdg bg-warning plain">Off by '+money(Math.abs(expected-o.rawTotal))+'</span></div>';
}
function openOrderPanel(oid){
  var o=orders.find(function(x){ return x._docId===oid||x.id===oid; });
  if(!o) return;
  $('sp-sub').textContent='Order Details';
  $('sp-title').textContent=shortId(o.id);
  var steps=['Placed','Confirmed','Picked Up','On the Way','Delivered'];
  var sfMap={pending:1,confirmed:2,picked_up:3,in_transit:4,delivered:5,
    Pending:1,Confirmed:2,'Picked Up':3,'On the Way':4,Delivered:5};
  var idx=sfMap[o.status]||1;
  if(isCancelledStatus(o.status)) idx=0;
  var flow='<div class="sf">';
  steps.forEach(function(s,i){
    var state=i<idx-1?'done':(i===idx-1?'done current':'');
    flow+='<div class="sf-wrap"><div class="sf-dot '+state+'"></div><div class="sf-lbl">'+s+'</div></div>';
    if(i<steps.length-1) flow+='<div class="sf-line'+(i<idx-1?' done':'')+'"></div>';
  });
  flow+='</div><div style="text-align:center;margin-bottom:16px">'+badge(o.status)+'</div>';

  var itemsHtml=(o.items||[]).map(function(item){
    if(item&&typeof item==='object'){
      var qty=item.quantity||1;
      var price=item.price!=null?money(item.price):'—';
      return '<div class="sp-row"><span class="sp-lbl">'+esc(item.name||item.title||'Item')+'</span>'+
             '<span class="sp-val num">'+qty+'× '+price+'</span></div>';
    }
    return '<div class="sp-row"><span class="sp-lbl">'+esc(item)+'</span></div>';
  }).join('');
  if(!itemsHtml) itemsHtml='<div class="empty-copy">No items listed on this order.</div>';

  var di=o.driverId?drivers.find(function(x){ return x.id===o.driverId; }):null;
  var dp=di?di.phone:(o.driverPhone||'—');

  /* ── P5-06: the data the order already carried and nobody could see ──── */

  // A package job has no merchant and no line items; its detail lives in the
  // `package` map (P5-01). Rendering it under "Items" would be a lie of layout.
  var pkg=o.pkg;
  var packageHtml=pkg?
    '<div class="sp-sec"><div class="sp-sec-title">Package</div>'+
      row('Contents',esc(pkg.itemCategory||'—'))+
      row('Pickup','<span class="sp-val sm">'+esc(pkg.pickupAddress||'—')+'</span>',true)+
      row('Weight',esc(pkg.weightKg!=null?pkg.weightKg+' kg':'—')+
        (pkg.weightBand?' <span class="sp-val sm">('+esc(pkg.weightBand)+')</span>':''))+
      row('Packing',pkg.packingRequired?'Requested':'Not requested')+
      (pkg.instructions?row('Instructions','<span class="sp-val sm">'+esc(pkg.instructions)+'</span>',true):'')+
    '</div>':'';

  /* Proof of delivery. The driver has been photographing every handover since
     Phase 1 and uploading it; `deliveryPhotoUrl` was written to the order and
     read by absolutely nothing. A disputed delivery could not be settled with
     evidence the system already held. */
  var proofHtml=(o.deliveryPhotoUrl||o.deliveryNote)?
    '<div class="sp-sec"><div class="sp-sec-title">Proof of Delivery</div>'+
      (o.deliveryPhotoUrl?
        '<a class="sp-proof" href="'+esc(o.deliveryPhotoUrl)+'" target="_blank" rel="noopener noreferrer">'+
          '<img src="'+esc(o.deliveryPhotoUrl)+'" alt="Delivery photo for order '+esc(o.id)+'" loading="lazy"/>'+
        '</a>':'')+
      (o.deliveryNote?row('Driver note','<span class="sp-val sm">'+esc(o.deliveryNote)+'</span>',true):'')+
    '</div>':'';

  var cancelHtml=isCancelledStatus(o.status)?
    '<div class="sp-sec"><div class="sp-sec-title">Cancellation</div>'+
      row('Cancelled by',esc(o.cancelledBy||'—'))+
      // An empty reason is shown as such rather than hidden: "no reason
      // recorded" is itself the finding when cancellations are being reviewed.
      row('Reason','<span class="sp-val sm">'+esc(o.cancellationReason||'No reason recorded')+'</span>',true)+
    '</div>':'';

  /* Every transition timestamp, in lifecycle order. Only the ones that
     happened are listed — a row of em-dashes for a stage the order has not
     reached reads as missing data rather than as the future. */
  var stampRows=[['createdAt','Placed'],['acceptedAt','Driver accepted'],
    ['assignedAt','Admin assigned'],['pickedUpAt','Picked up'],
    ['inTransitAt','On the way'],['deliveredAt','Delivered'],
    ['cancelledAt','Cancelled'],['ratedAt','Rated']]
    .map(function(pair){
      var v=fmtStamp((o.stamps||{})[pair[0]]);
      return v?row(pair[1],'<span class="sp-val sm num">'+esc(v)+'</span>',true):'';
    }).join('');
  var timelineHtml=stampRows?
    '<div class="sp-sec"><div class="sp-sec-title">Timeline</div>'+stampRows+
      (o.assignedBy?row('Assigned by','<span class="sp-val sm">'+esc(o.assignedBy)+'</span>',true):'')+
    '</div>':'';

  $('sp-body').innerHTML=
    '<div class="sp-sec"><div class="sp-sec-title">Status Flow</div>'+flow+'</div>'+
    cancelHtml+
    '<div class="sp-sec"><div class="sp-sec-title">Customer</div>'+
      row('Name',esc(o.customer))+row('Phone',esc(phoneFmt(o.custPhone)))+
      row('Delivery Address','<span class="sp-val sm">'+esc(o.address)+'</span>',true)+
      row('Payment',esc(o.payment))+
    '</div>'+
    // A package order has no merchant, so it gets the Package block instead of
    // a Merchant block full of placeholders.
    (pkg?packageHtml:
      '<div class="sp-sec"><div class="sp-sec-title">Merchant</div>'+
        row('Name',esc(o.merchant))+
        row('Address','<span class="sp-val sm">'+esc(o.merchantAddr)+'</span>',true)+
      '</div>')+
    '<div class="sp-sec"><div class="sp-sec-title">Driver</div>'+
      row('Name',esc(o.driver))+row('Phone',esc(phoneFmt(dp)))+
    '</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Order Total</div>'+
      /* P3-02: the breakdown, not just the charged amount. Without the discount
         line a discounted order shows a total that does not match its items,
         and nothing on screen explains the gap. */
      (o.subtotal!=null?'<div class="sp-row"><span class="sp-lbl">Subtotal</span><span class="sp-val num">'+money(o.subtotal)+'</span></div>':'')+
      (o.orderDeliveryFee!=null?'<div class="sp-row"><span class="sp-lbl">Delivery fee</span><span class="sp-val num">'+(o.orderDeliveryFee===0?'Free':money(o.orderDeliveryFee))+'</span></div>':'')+
      (o.serviceFee!=null?'<div class="sp-row"><span class="sp-lbl">Service fee</span><span class="sp-val num">'+money(o.serviceFee)+'</span></div>':'')+
      (o.discount>0?'<div class="sp-row"><span class="sp-lbl">Discount'+(o.promoCode?' ('+esc(o.promoCode)+')':'')+'</span><span class="sp-val num">-'+money(o.discount)+'</span></div>':'')+
      '<div class="sp-row"><span class="sp-lbl">Amount</span><span class="sp-val money">'+esc(o.amount)+'</span></div>'+
      reconcileNote(o)+
      (o.driverCommission!=null?'<div class="sp-row"><span class="sp-lbl">Driver commission</span><span class="sp-val num">'+money(o.driverCommission)+'</span></div>':'')+
    '</div>'+
    (pkg?'':'<div class="sp-sec"><div class="sp-sec-title">Items</div>'+itemsHtml+'</div>')+
    proofHtml+
    timelineHtml+
    '<div class="sp-sec"><div class="sp-sec-title">Admin Actions</div>'+
      '<div class="fr"><label for="sp-assign-driver">Assign Driver</label>'+
        '<select id="sp-assign-driver"><option value="">— Unassigned —</option>'+
          drivers.filter(function(d){ return d.approved; }).map(function(d){
            return '<option value="'+esc(d.id)+'"'+(o.driverId===d.id?' selected':'')+'>'+
              esc(d.name)+(d.isOnline?' (online)':' (offline)')+'</option>';
          }).join('')+
        '</select></div>'+
      '<div class="fr"><label for="sp-update-status">Update Status</label>'+
        '<select id="sp-update-status">'+
          OrderStatus.selectableFrom(o.status).map(function(s){
            return '<option value="'+esc(s)+'"'+(o.status===s?' selected':'')+'>'+esc(STATUS_LABEL[s]||s)+'</option>';
          }).join('')+
        '</select></div>'+
      '<button class="btn btn-primary btn-block" id="sp-save-btn" data-action="save-order" data-oid="'+esc(o._docId)+'">'+
        icon('check')+'Save Changes</button>'+
    '</div>';
  openSidePanel();
}
function row(label,valueHtml,raw){
  return '<div class="sp-row"><span class="sp-lbl">'+label+'</span>'+
    (raw?valueHtml:'<span class="sp-val">'+valueHtml+'</span>')+'</div>';
}
/** Applies the admin's driver and status edits to an order.
 *
 *  Runs in a transaction that re-reads the order, mirroring the driver app's
 *  acceptOrder. The previous blind updateDoc meant two admins on two browsers —
 *  or an admin racing a driver's Accept tap — produced a silent
 *  last-write-wins steal.
 *
 *  Three defects fixed here:
 *
 *  1. Assigning a driver left status untouched. The order then satisfied
 *     NEITHER driver query: the available pool wants driverId == null, and the
 *     active-order stream wants a driver-held status. The order became
 *     invisible to every driver, including the assigned one, while the
 *     customer's tracker showed their name. It was never delivered.
 *
 *  2. The '— Unassigned —' option's value is '', and the old `if(driverId)`
 *     guard meant selecting it did nothing at all, silently.
 *
 *  3. Any status could be written over any other. Now only legal transitions.
 */
function saveOrderChanges(docId){
  var sel=$('sp-assign-driver'), statusSel=$('sp-update-status');
  var driverId=sel?sel.value:'';
  var status=statusSel?statusSel.value:'';
  var order=orders.find(function(o){ return o._docId===docId; });
  var wasAssigned=order?(order.driverId||''):'';
  var unassigning=driverId===''&&wasAssigned!=='';
  var assigning=driverId!==''&&driverId!==wasAssigned;
  var changingStatus=status!==''&&order&&status!==order.status;

  if(!assigning&&!unassigning&&!changingStatus){
    toast('warning','Nothing to save — pick a driver or a status first.');
    return;
  }

  if(changingStatus&&!OrderStatus.canTransition(order.status,status)){
    toast('error','An order in "'+(STATUS_LABEL[order.status]||order.status)+
      '" cannot move to "'+(STATUS_LABEL[status]||status)+'".','Illegal status change');
    return;
  }

  var btn=$('sp-save-btn');
  function busy(on){
    if(!btn) return;
    btn.disabled=on;
    btn.innerHTML=on?'<span class="spin"></span>Saving…':icon('check')+'Save Changes';
  }

  function apply(){
    busy(true);
    runTransaction(db,function(tx){
      var ref=doc(db,'orders',docId);
      return tx.get(ref).then(function(snap){
        if(!snap.exists()) throw new Error('This order no longer exists.');
        var cur=snap.data();
        var curStatus=cur.status||OrderStatus.PENDING;
        var curDriver=cur.driverId||'';

        // Someone else claimed it between render and save.
        if(assigning&&curDriver&&curDriver!==driverId&&curDriver!==wasAssigned){
          throw new Error('Another driver already claimed this order.');
        }

        var upd={updatedAt:serverTimestamp()};

        if(assigning){
          var drv=drivers.find(function(d){ return d.id===driverId; });
          if(!drv) throw new Error('That driver is no longer available.');
          upd.driverId=driverId;
          upd.driverName=drv.name;
          upd.driverPhone=drv.phone||null;
          upd.assignedBy=auth.currentUser?auth.currentUser.email:'admin';
          upd.assignedAt=serverTimestamp();
          // The fix for defect 1: a pending order must advance to confirmed in
          // the SAME write, or no driver query will ever return it.
          if(curStatus===OrderStatus.PENDING&&!changingStatus){
            upd.status=OrderStatus.CONFIRMED;
          }
        }

        if(unassigning){
          upd.driverId=null;
          upd.driverName=null;
          upd.driverPhone=null;
          upd.assignedBy=null;
          upd.assignedAt=null;
          // Back into the available pool, which filters on pending.
          if(!changingStatus&&OrderStatus.isDriverHeld(curStatus)){
            upd.status=OrderStatus.PENDING;
          }
        }

        if(changingStatus){
          // Re-check against the live value, not what the panel rendered.
          if(!OrderStatus.canTransition(curStatus,status)){
            throw new Error('This order moved to "'+(STATUS_LABEL[curStatus]||curStatus)+
              '" while you were editing. Reopen it and try again.');
          }
          upd.status=status;
          if(status===OrderStatus.CANCELLED){
            upd.cancelledAt=serverTimestamp();
            upd.cancelledBy='admin';
          }
        }

        tx.update(ref,upd);
      });
    }).then(function(){
      closeSidePanel();
      toast('success',unassigning?'Driver unassigned — order returned to the pool.':'Order updated.');
    }).catch(function(e){
      toast('error',e.message,'Could not update order');
      busy(false);
    });
  }

  // Warn before cancelling an order a driver is physically holding.
  if(changingStatus&&status===OrderStatus.CANCELLED&&
     OrderStatus.isDriverHeld(order.status)&&order.driver&&order.driver!=='—'){
    confirmDialog({
      title:'Cancel this order?',
      body:'Driver '+order.driver+' is currently delivering this order and will be notified. '+
           'They may already have collected the goods.',
      confirmLabel:'Cancel order',
      tone:'warning'
    }).then(function(ok){ if(ok) apply(); });
    return;
  }

  apply();
}

// ══════════════════════ DRIVERS (DV-1 … DV-8) ══════════════════════
var driverFilter='',driverSearch='';

/* Which filter bucket a driver falls in — matches the #drv-filter options. */
function driverInBucket(d,b){
  if(!b) return true;
  if(b==='online') return d.status==='Online';
  if(b==='ondelivery') return d.status==='On Delivery';
  if(b==='available') return d.available;
  if(b==='offline') return d.status==='Offline';
  if(b==='pending') return d.rawStatus==='pending';
  if(b==='paused') return d.rawStatus==='paused';
  if(b==='suspended') return d.rawStatus==='suspended';
  if(b==='rejected') return d.rawStatus==='rejected';
  return true;
}
function driverMatchesSearch(d,q){
  if(!q) return true;
  return [d.name,d.plate,d.phone,phoneFmt(d.phone),d.vtype,d.email]
    .join(' ').toLowerCase().indexOf(q)>-1;
}

/* The order this driver is holding right now, if any (DV-6). */
function driverActiveOrder(d){
  return orders.find(function(o){
    return (o.driverId===d.id||o.driver===d.name)&&OrderStatus.isDriverHeld(o.status);
  })||null;
}

function renderDrivers(){
  var el=$('drivers-stats');
  if(el){
    var onlineC=drivers.filter(function(d){ return d.status==='Online'||d.status==='On Delivery'; }).length;
    var delC=drivers.filter(function(d){ return d.status==='On Delivery'; }).length;
    var pendC=drivers.filter(function(d){ return d.rawStatus==='pending'; }).length;
    el.innerHTML=
      statCard('drivers','Total Drivers',drivers.length,'','')+
      statCard('bolt','Online',onlineC,delC+' on a delivery','success')+
      statCard('orders','Available',drivers.filter(function(d){ return d.available; }).length,'Online and free','ocean')+
      statCard('clock','Pending Approval',pendC,'Awaiting review','gold');
  }
  var grid=$('drivers-grid'); if(!grid) return;
  if(!loadedOnce.drivers){
    grid.innerHTML=Array.from({length:6}).map(function(){
      return '<div class="dcard"><div class="sk sk-line" style="width:55%"></div>'+
        '<div class="sk sk-line" style="width:75%;margin-top:10px"></div>'+
        '<div class="sk sk-line" style="width:40%;margin-top:10px"></div></div>';
    }).join('');
    return;
  }
  if(!drivers.length){
    grid.innerHTML='<div class="dcard-empty">'+emptyState('users','No drivers yet','Add your first driver, or wait for a rider to sign up in the driver app.')+'</div>';
    return;
  }
  var rows=drivers.filter(function(d){ return driverInBucket(d,driverFilter)&&driverMatchesSearch(d,driverSearch); });
  if(!rows.length){
    grid.innerHTML='<div class="dcard-empty">'+emptyState('search','No matching drivers','Nothing matched the current filter and search.')+'</div>';
    return;
  }
  grid.innerHTML=rows.map(driverCard).join('');
}

/* One driver card, per the client's exact layout (DV-8):
     🟢 Touseef Zahid                     [status]
     Motorcycle • Plate HKD2728
     ⭐ 4.9 • 42 deliveries
     Available / View Active Delivery
     View | Assign  (+ state actions)                             */
function driverCard(d){
  var dotCls=d.status==='Online'?'on':(d.status==='On Delivery'?'busy':(d.rawStatus==='paused'||d.rawStatus==='pending'?'warn':(d.rawStatus==='suspended'||d.rawStatus==='rejected'?'off':'')));
  var rate=(Number(d.rating)||0).toFixed(1);
  var stats=d.ratingTotal
    ? '<svg class="ic dc-star" aria-hidden="true"><use href="#i-star-f"/></svg>'+rate+' • '+d.trips+' deliver'+(d.trips===1?'y':'ies')
    : 'No ratings yet • '+d.trips+' deliver'+(d.trips===1?'y':'ies');

  var active=driverActiveOrder(d);
  var availLine;
  if(active) availLine='<button class="pa-btn" data-action="driver-active-delivery" data-id="'+esc(d.id)+'">'+icon('orders')+' View active delivery — '+esc(shortId(active.id))+'</button>';
  else if(d.available) availLine='<span class="dc-avail">Available</span>';
  else if(d.status==='Online') availLine='<span class="dc-avail">Online</span>';
  else availLine='<span class="dc-avail muted">'+esc(d.status)+'</span>';

  // Primary actions — "View | Assign" as the client asked, always present.
  var acts='<button class="pa-btn" data-action="view-driver" data-id="'+esc(d.id)+'">View</button>';
  if(d.rawStatus==='approved') acts+='<button class="pa-btn" data-action="driver-assign" data-id="'+esc(d.id)+'">Assign</button>';

  // State actions depend on where the driver is in their lifecycle.
  if(d.rawStatus==='pending'){
    acts+='<button class="pa-btn" data-action="driver-review" data-id="'+esc(d.id)+'">Review documents</button>'+
      '<button class="pa-btn pa-ok" data-action="approve-driver" data-id="'+esc(d.id)+'">Approve</button>'+
      '<button class="pa-btn pa-del" data-action="reject-driver" data-id="'+esc(d.id)+'">Reject</button>';
  }else if(d.rawStatus==='rejected'){
    acts+='<button class="pa-btn pa-ok" data-action="approve-driver" data-id="'+esc(d.id)+'">Re-approve</button>';
  }else if(d.rawStatus==='paused'){
    acts+='<button class="pa-btn pa-ok" data-action="driver-resume" data-id="'+esc(d.id)+'">Resume</button>'+
      '<button class="pa-btn pa-del" data-action="driver-suspend" data-id="'+esc(d.id)+'">Suspend</button>';
  }else if(d.rawStatus==='suspended'){
    acts+='<button class="pa-btn pa-ok" data-action="driver-reinstate" data-id="'+esc(d.id)+'">Reinstate</button>';
  }else{ // approved
    acts+='<button class="pa-btn" data-action="driver-pause" data-id="'+esc(d.id)+'">Pause</button>'+
      '<button class="pa-btn pa-del" data-action="driver-suspend" data-id="'+esc(d.id)+'">Suspend</button>';
  }
  acts+='<button class="pa-btn" data-action="edit-driver" data-id="'+esc(d.id)+'">Edit</button>'+
    '<button class="pa-btn pa-del" data-action="del-driver" data-id="'+esc(d.id)+'">Delete</button>';

  // DV-1: online toggle sits by the status for an approved driver.
  var toggle=d.rawStatus==='approved'
    ? '<label class="tgl" title="Toggle online"><input type="checkbox"'+(d.isOnline?' checked':'')+
        ' class="tgl-driver-online" data-id="'+esc(d.id)+'" aria-label="Driver online"><span class="ts"></span></label>'
    : '';

  return '<div class="dcard">'+
    '<div class="dc-head">'+
      '<span class="dot '+dotCls+'"></span>'+
      '<b class="dc-name">'+esc(d.name)+'</b>'+
      '<span class="dc-badges">'+badge(d.status)+toggle+'</span>'+
    '</div>'+
    '<div class="dc-line">'+esc(d.vtype)+' • Plate '+esc(d.plate)+'</div>'+
    '<div class="dc-line dc-stats">'+stats+'</div>'+
    '<div class="dc-line">'+availLine+'</div>'+
    '<div class="dc-acts">'+acts+'</div>'+
  '</div>';
}
function statCard(ic,label,value,sub,accent){
  var a=accent?' ac-'+accent:'';
  var c=accent?' c-'+accent:'';
  return '<div class="sc'+a+'"><div class="sc-top"><div><div class="sc-lbl">'+esc(label)+'</div>'+
    '<div class="sc-val num">'+esc(String(value))+'</div></div>'+
    '<div class="sc-chip'+c+'">'+icon(ic)+'</div></div>'+
    (sub?'<div class="sc-sub">'+esc(sub)+'</div>':'')+'</div>';
}

/* Blank placeholders read as data in this form — an empty Vehicle Model looked
   identical to one that genuinely says "—", which is what the mirror stores for
   "not given". Strip the sentinel on the way into the form so the placeholder
   shows through, and put it back on the way out. */
function unDash(v){ return (v==null||v==='—')?'':String(v); }

/** Labels, field states and helper text for whichever mode the modal is in. */
function setDriverModalMode(mode){
  driverMode=mode;
  var isEdit=mode==='edit';
  $('drv-modal-title').textContent=isEdit?'Edit Driver':'Add New Driver';
  $('drv-save-btn').innerHTML=icon('check')+(isEdit?'Update':'Add Driver');
  /* Once the driver exists, "Cancel" is a lie — there is nothing left to
     abandon, and an admin who reads it as "undo that" will click it expecting
     the driver to go away. */
  $('drv-cancel-btn').textContent=isEdit?'Close':'Cancel';
  // The email is the Auth account key. Changing it would need the Admin SDK,
  // and letting it be typed over would silently detach the profile from the
  // login behind it.
  $('d-email').readOnly=isEdit;
  $('d-email-note').textContent=isEdit
    ? 'This is the driver\'s username in the ShipEast Driver app. It cannot be changed — it is the account key.'
    : 'This is the driver\'s username in the ShipEast Driver app. It cannot be changed later — it is the account key.';
  $('drv-pass-row').hidden=isEdit;
  $('drv-reset-row').hidden=!isEdit;
  syncDriverStatusNote();
}
var DRIVER_STATUS_NOTE={
  approved:'The driver can sign in and start receiving orders immediately.',
  pending:'The driver can sign in, but the app holds them on the “awaiting approval” screen until you approve them.',
  rejected:'The driver is taken offline and blocked from working. You can re-approve them later from the roster.'
};
function syncDriverStatusNote(){
  var el=$('d-status-note'); if(!el) return;
  el.textContent=DRIVER_STATUS_NOTE[($('d-status')||{}).value]||'';
}

function openDriverModal(mode,id){
  driverEditId=(mode==='edit')?(id||null):null;
  var d=(mode==='edit')?drivers.find(function(x){ return x.id===id; }):null;
  $('d-name').value    =d?unDash(d.name):'';
  $('d-phone').value   =d?unDash(d.phone):'';
  $('d-email').value   =d?unDash(d.email):'';
  $('d-vtype').value   =d?(d.vtype||'Car'):'Car';
  $('d-vehicle').value =d?unDash(d.vehicle):'';
  $('d-plate').value   =d?unDash(d.plate):'';
  $('d-dlicence').value=d?unDash(d.dlicence):'';
  $('d-status').value  =d?(d.rawStatus||'pending'):'approved';
  $('d-pass').value    ='';
  setDriverModalMode(mode);
  if(mode==='edit'&&id) loadDriverLicence(id);
  openModal('modal-driver');
}

/* Readable rather than maximally random: this password gets read aloud or typed
   into a phone by hand, so it avoids the character pairs that get misheard or
   mistyped (0/O, 1/l/I) and keeps a shape a person can dictate. ~34 bits from
   crypto.getRandomValues, which is far past what a rate-limited Firebase
   sign-in endpoint can be attacked through, and it is replaced by whatever the
   driver chooses the first time they reset it. */
function generatePassword(){
  var words='bolt,reef,palm,dock,cane,surf,jade,mango,coral,ridge,tide,kite'.split(',');
  var bytes=new Uint32Array(3);
  crypto.getRandomValues(bytes);
  var w1=words[bytes[0]%words.length];
  var w2=words[bytes[1]%words.length];
  var n=100+(bytes[2]%900);
  return w1.charAt(0).toUpperCase()+w1.slice(1)+'-'+w2+'-'+n;
}
function fillGeneratedPassword(){
  var el=$('d-pass'); if(!el) return;
  el.value=generatePassword();
  el.focus(); el.select();
}
/* The licence number lives in drivers/{uid}/private/identity (P4-05), not on
   the parent document. Old records still hold it on the parent; the mirror's
   `dlicence` covers those, and this overwrites it when the private copy
   exists. Async on purpose — the modal must open immediately. */
function loadDriverLicence(id){
  getDoc(doc(db,'drivers',id,'private','identity')).then(function(snap){
    if(!snap.exists()||driverEditId!==id) return;
    var v=snap.data().licenceNumber;
    if(v) $('d-dlicence').value=v;
  }).catch(function(){ /* no private record, or no access — keep what we have */ });
}
/* ══════════════════════ DRIVER PROVISIONING ══════════════════════
   Why this is done in the browser, and why that is not a shortcut.

   The history: "Add Driver" originally called addDoc, producing
   drivers/{randomId} with no Auth account behind it. That person could never
   sign in, and when they eventually self-registered they got a SECOND document,
   leaving the first as an orphan that still appeared in the roster and could
   still be "approved" — approving nobody. P4-05 moved creation to a callable,
   `createDriverAccount`, so the account and the document would be made together
   by the Admin SDK.

   That callable has never run. Cloud Functions is a Blaze-plan product and this
   project is on Spark: the Cloud Functions API has not been enabled on
   shipeast-1a1f6 at all, so the endpoint does not exist. The Functions client
   SDK cannot parse the 404 that comes back and reports it as code 'internal'
   with the message 'internal' — which is exactly the "Could not add driver /
   internal" toast, and why no message in it pointed anywhere useful.

   So the account is created here instead, through a SECOND Firebase app
   instance. Two properties make that safe rather than a hack:

     1. It cannot disturb the admin's session. Auth state is per-app-instance,
        so createUserWithEmailAndPassword on 'se-provision' signs that instance
        in as the new driver and leaves the primary app untouched. Persistence
        is in-memory, so nothing is written to disk and a refresh cannot
        resurrect the driver's session in this browser.

     2. It does not need a rule to be loosened. firestore.rules deliberately
        allows a driver document to be created ONLY by its own uid, and only as
        status:'pending' with totalTrips:0 — that is invariant 1 of the rules
        file, "a driver cannot approve themselves". The provisioning instance IS
        that uid at the moment of the write, so it satisfies the rule as written.
        Approving the driver afterwards is a separate write, made by the admin
        under isAdmin(), which is exactly the separation the rule exists to
        enforce.

   What is genuinely lost without the Admin SDK: the admin cannot change an
   existing driver's password (see resetDriverPassword), and cannot change their
   email. Both are stated in the form rather than silently missing. */
var provisionApp=null,provisionAuth=null,provisionDb=null;
function provisionHandles(){
  if(!provisionApp){
    provisionApp=initializeApp(firebaseConfig,'se-provision');
    provisionAuth=getAuth(provisionApp);
    provisionDb=getFirestore(provisionApp);
    if(USE_EMULATORS){
      connectAuthEmulator(provisionAuth,'http://localhost:'+EMULATORS.auth,{disableWarnings:true});
      connectFirestoreEmulator(provisionDb,'localhost',EMULATORS.firestore);
    }
  }
  return {auth:provisionAuth,db:provisionDb};
}

/** Firebase's auth/* codes, translated into something an operator can act on. */
var DRIVER_AUTH_MSG={
  'auth/email-already-in-use':'An account already exists for that email — the driver may have signed up themselves. Find them in the roster and use Edit instead of Add.',
  'auth/invalid-email':'That email address is not valid.',
  'auth/weak-password':'That password is too short. Firebase requires at least 6 characters.',
  'auth/operation-not-allowed':'Email/password sign-in is switched off for this project. Enable it under Firebase Console → Authentication → Sign-in method.',
  'auth/too-many-requests':'Too many attempts from this browser. Wait a minute and try again.',
  'auth/network-request-failed':'The network request failed. Check the connection and try again.'
};
function authMessage(e){
  return DRIVER_AUTH_MSG[e&&e.code]||(e&&e.message)||'Something went wrong.';
}

/**
 * Creates the login and the roster entry together, keyed by the same uid.
 *
 * Resolves with the new uid. The document is always written as pending, because
 * that is the only shape the create rule accepts; promoting it is the caller's
 * separate, admin-authenticated write.
 */
function provisionDriver(input){
  var h=provisionHandles();
  var uid=null;
  return setPersistence(h.auth,inMemoryPersistence)
    .then(function(){ return createUserWithEmailAndPassword(h.auth,input.email,input.password); })
    .then(function(cred){
      uid=cred.user.uid;
      return setDoc(doc(h.db,'drivers',uid),{
        name:input.name,
        email:input.email,
        phone:input.phone||'—',
        vehicleType:input.vehicleType,
        vehicleModel:input.vehicleModel||'—',
        licencePlate:input.licencePlate||'—',
        // Required verbatim by the create rule. Never a status the admin picked.
        status:'pending',
        totalTrips:0,
        isOnline:false,
        onDelivery:false,
        ratingCount:0,
        averageRating:0,
        todayEarnings:0,
        createdBy:'admin',
        createdAt:serverTimestamp(),
        updatedAt:serverTimestamp()
      });
    })
    .then(function(){
      /* licenceNumber is deliberately NOT on the parent document. drivers/{uid}
         is readable by every signed-in user — it has to be, because the
         customer's tracking card shows the name and vehicle of the driver
         bringing their order — so a licence number there is readable by every
         customer who ever placed an order. */
      if(!input.licenceNumber) return null;
      return setDoc(doc(h.db,'drivers',uid,'private','identity'),
        {licenceNumber:input.licenceNumber,updatedAt:serverTimestamp()},{merge:true});
    })
    .then(function(){
      // Drop the driver's session from this browser. Failing to sign out is not
      // worth failing the provisioning over — persistence is in-memory, so the
      // worst case ends at the next page load.
      return signOut(h.auth).catch(function(){});
    })
    .then(function(){ return uid; })
    .catch(function(e){
      /* An Auth account with no roster document is the one outcome worth naming
         explicitly: the email is now taken, so a retry hits
         email-already-in-use and reads like a different problem entirely. */
      if(uid){
        var err=new Error('The login was created but the driver profile could not be saved: '+
          authMessage(e)+' The email '+input.email+' is now taken — reload and use Edit to finish the profile.');
        err.partial=true;
        throw err;
      }
      throw new Error(authMessage(e));
    });
}

function saveDriver(){
  var name=$('d-name').value.trim();
  if(!name){ toast('warning','Full name is required.'); $('d-name').focus(); return; }
  var licence=$('d-dlicence').value.trim();
  var status=$('d-status').value;
  var btn=$('drv-save-btn'), isEdit=driverMode==='edit';
  function restore(){ btn.disabled=false; btn.innerHTML=icon('check')+(isEdit?'Update':'Add Driver'); }

  if(!isEdit){
    var email=$('d-email').value.trim().toLowerCase();
    var pass=$('d-pass').value;
    if(!email){ toast('warning','An email address is required — it is how the driver signs in.'); $('d-email').focus(); return; }
    if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)){
      toast('warning','That does not look like an email address.'); $('d-email').focus(); return;
    }
    if(pass.length<6){
      toast('warning','Set a password of at least 6 characters — the driver signs in with it.');
      $('d-pass').focus(); return;
    }
    btn.disabled=true; btn.innerHTML='<span class="spin"></span>Creating account…';

    provisionDriver({
      email:email,password:pass,name:name,
      phone:phoneFmt($('d-phone').value),
      vehicleType:$('d-vtype').value,
      vehicleModel:$('d-vehicle').value.trim(),
      licencePlate:$('d-plate').value.trim().toUpperCase(),
      licenceNumber:licence
    }).then(function(uid){
      // Only now, and only as the admin: the create rule forbids any other
      // starting status, and this write is what the rule wants an admin to make.
      if(status==='pending') return uid;
      return updateDoc(doc(db,'drivers',uid),{
        status:status,
        isOnline:false,
        updatedAt:serverTimestamp()
      }).then(function(){ return uid; })
        .catch(function(e){
          toast('warning','Driver created, but the status stayed "pending": '+e.message+
            ' Approve them from the roster.');
          return uid;
        });
    }).then(function(uid){
      /* Stay open and switch to edit mode rather than closing. The driver now
         exists, so the form's job changes from "create" to "amend", and the
         buttons say so — Cancel becomes Close, Add Driver becomes Update. The
         typed values are left in place: the drivers listener has usually not
         delivered the new document yet, so re-reading from the mirror would
         blank a form the admin is still looking at. */
      driverEditId=uid;
      setDriverModalMode('edit');
      restore();
      showCredentials(email,pass);
    }).catch(function(e){
      toast('error',e.message,'Could not add driver');
      restore();
    });
    return;
  }

  /* ── Edit ──────────────────────────────────────────────────────────────
     isOnline is the driver's own presence flag, set by their app when they go
     on shift. The old code wrote `isOnline: active` here, which meant editing a
     driver's phone number forced them online whether their app was running or
     not. It is only ever forced FALSE now, and only when the status being saved
     means they must not be working. */
  var obj={name:name,phone:phoneFmt($('d-phone').value)||'—',
    vehicleType:$('d-vtype').value,vehicleModel:$('d-vehicle').value.trim()||'—',
    licencePlate:$('d-plate').value.trim().toUpperCase()||'—',
    status:status,
    updatedAt:serverTimestamp()};
  if(status!=='approved') obj.isOnline=false;
  btn.disabled=true; btn.innerHTML='<span class="spin"></span>Saving…';
  updateDoc(doc(db,'drivers',driverEditId),obj)
    .then(function(){
      if(!licence) return null;
      return setDoc(doc(db,'drivers',driverEditId,'private','identity'),
        {licenceNumber:licence,updatedAt:serverTimestamp()},{merge:true});
    })
    .then(function(){
      closeModal('modal-driver'); restore();
      toast('success','Driver updated.');
    }).catch(function(e){
      toast('error',e.message,'Could not save driver'); restore();
    });
}

/* Changing another account's password needs the Admin SDK. A reset email is the
   one route a client has, and it is the honest one: the driver proves they
   control the address and chooses their own password. */
function resetDriverPassword(){
  var email=($('d-email').value||'').trim();
  if(!email){ toast('warning','No email address on this driver.'); return; }
  confirmDialog({
    tone:'warning',
    title:'Send a password reset link?',
    body:'Firebase will email '+email+' a link to choose a new password. Their current '+
         'password keeps working until they use it.',
    confirmLabel:'Send link'
  }).then(function(ok){
    if(!ok) return;
    sendPasswordResetEmail(auth,email)
      .then(function(){ toast('success','Reset link sent to '+email+'.'); })
      .catch(function(e){ toast('error',authMessage(e),'Could not send the link'); });
  });
}

/* Shown once, on screen, for the admin to hand over. The password is not stored
   anywhere it could be read back — Firebase keeps only a hash — so this dialog
   is the only chance to record it, and it says so. */
function showCredentials(email,pass){
  $('cf-ico').className='m-ico warning';
  $('cf-ico').innerHTML=icon('check','ic-lg');
  $('cf-title').textContent='Driver added — sign-in details';
  $('cf-body').innerHTML=
    'Give these to the driver for the ShipEast Driver app. The password cannot be '+
    'shown again after you close this.'+
    '<div class="cred-box">'+
      '<div class="cred-row"><span>Email</span><b>'+esc(email)+'</b></div>'+
      '<div class="cred-row"><span>Password</span><b>'+esc(pass)+'</b></div>'+
    '</div>';
  var ok=$('cf-ok'); ok.textContent='Copy details'; ok.className='btn btn-primary';
  confirmResolve=function(copy){
    $('cf-body').innerHTML='';
    if(!copy) return;
    navigator.clipboard.writeText('ShipEast Driver app\nEmail: '+email+'\nPassword: '+pass)
      .then(function(){ toast('success','Sign-in details copied.'); })
      .catch(function(){ toast('warning','Copy failed — select the details and copy them manually.'); });
  };
  openModal('modal-confirm');
}
function deleteDriver(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  confirmDialog({title:'Delete driver?',body:'“'+d.name+'” will be permanently removed. This cannot be undone.',confirmLabel:'Delete driver'})
    .then(function(ok){
      if(!ok) return;
      deleteDoc(doc(db,'drivers',id))
        .then(function(){ toast('success','Driver deleted.'); })
        .catch(function(e){ toast('error',e.message,'Delete failed'); });
    });
}
function approveDriver(id){
  updateDoc(doc(db,'drivers',id),{status:'approved',updatedAt:serverTimestamp()})
    .then(function(){ closeSidePanel(); toast('success','Driver approved.'); })
    .catch(function(e){ toast('error',e.message,'Approval failed'); });
}
function rejectDriver(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  confirmDialog({title:'Reject application?',body:'“'+d.name+'” will be marked rejected and taken offline. You can re-approve later.',confirmLabel:'Reject',tone:'warning'})
    .then(function(ok){
      if(!ok) return;
      updateDoc(doc(db,'drivers',id),{status:'rejected',isOnline:false,updatedAt:serverTimestamp()})
        .then(function(){ closeSidePanel(); toast('info','Driver rejected.'); })
        .catch(function(e){ toast('error',e.message,'Could not reject'); });
    });
}
function toggleDriverOnline(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  updateDoc(doc(db,'drivers',id),{isOnline:!d.isOnline,updatedAt:serverTimestamp()})
    .catch(function(e){ toast('error',e.message,'Could not change status'); });
}

// ── DV-2: pause / suspend / resume / reinstate ─────────────────────────
/* Pause is the soft, reversible stop. It forces the driver offline (the app
   ejects them to the waiting screen) and can be undone with Resume. */
function pauseDriver(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  var active=driverActiveOrder(d);
  confirmDialog({title:'Pause '+d.name+'?',tone:'warning',
    body:(active?'They are currently on order '+shortId(active.id)+'. ':'')+
      'They will stop receiving new requests and be signed out of the app until you resume them.',
    confirmLabel:'Pause driver'})
    .then(function(ok){
      if(!ok) return;
      updateDoc(doc(db,'drivers',id),{status:'paused',isOnline:false,updatedAt:serverTimestamp()})
        .then(function(){ toast('success',d.name+' paused.'); })
        .catch(function(e){ toast('error',e.message,'Could not pause'); });
    });
}
/* Suspend is the hard stop — a conduct or safety matter. Same mechanics as
   pause, but the confirm spells out the consequence and the app shows the
   driver a suspension message, not a "paused" one. */
function suspendDriver(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  var active=driverActiveOrder(d);
  confirmDialog({title:'Suspend '+d.name+'?',tone:'warning',
    body:(active?'⚠️ They are currently delivering order '+shortId(active.id)+' and will be told to return the goods and contact support. ':'')+
      'The account is blocked from working until you reinstate it.',
    confirmLabel:'Suspend driver'})
    .then(function(ok){
      if(!ok) return;
      updateDoc(doc(db,'drivers',id),{status:'suspended',isOnline:false,updatedAt:serverTimestamp()})
        .then(function(){ toast('info',d.name+' suspended.'); })
        .catch(function(e){ toast('error',e.message,'Could not suspend'); });
    });
}
function resumeDriver(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  updateDoc(doc(db,'drivers',id),{status:'approved',updatedAt:serverTimestamp()})
    .then(function(){ toast('success',d.name+' is active again.'); })
    .catch(function(e){ toast('error',e.message,'Could not resume'); });
}
function reinstateDriver(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  confirmDialog({title:'Reinstate '+d.name+'?',
    body:'The account can sign in and accept deliveries again. They still need to toggle themselves online.',
    confirmLabel:'Reinstate',tone:'warning'})
    .then(function(ok){
      if(!ok) return;
      updateDoc(doc(db,'drivers',id),{status:'approved',updatedAt:serverTimestamp()})
        .then(function(){ toast('success',d.name+' reinstated.'); })
        .catch(function(e){ toast('error',e.message,'Could not reinstate'); });
    });
}

// ── DV-6: jump straight to the order a driver is holding ───────────────
function driverActiveDelivery(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  var o=driverActiveOrder(d);
  if(!o){ toast('info',d.name+' is not on a delivery right now.'); return; }
  openOrderPanel(o._docId||o.id);
}

// ── DV-7: assign this driver to a waiting order from their card ────────
function assignFromDriver(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  if(d.rawStatus!=='approved'){ toast('warning','Only an approved driver can be assigned.'); return; }
  // Unclaimed orders still waiting for a driver.
  var pool=orders.filter(function(o){ return o.status==='pending'&&!o.driverId; });
  if(!pool.length){ toast('info','No unassigned orders are waiting right now.'); return; }
  $('cf-ico').className='m-ico'; $('cf-ico').innerHTML=icon('drivers','ic-lg');
  $('cf-title').textContent='Assign '+d.name+' to an order';
  $('cf-body').innerHTML='<select id="cf-assign-order" style="width:100%;margin-top:8px">'+
    pool.slice(0,50).map(function(o){
      return '<option value="'+esc(o._docId||o.id)+'">'+esc(shortId(o.id))+' — '+esc(o.merchant)+' → '+esc(o.customer)+' ('+esc(o.amount)+')</option>';
    }).join('')+'</select>';
  var ok=$('cf-ok'); ok.textContent='Assign order'; ok.className='btn btn-primary';
  confirmResolve=function(confirmed){
    var oid=(($('cf-assign-order')||{}).value)||'';
    $('cf-body').innerHTML='';
    if(!confirmed||!oid) return;
    var o=orders.find(function(x){ return (x._docId||x.id)===oid; }); if(!o) return;
    // Mirror saveOrderChanges' assignment write: set the driver AND move the
    // order to 'confirmed' so it enters the driver's active-order query.
    runTransaction(db,function(tx){
      var ref=doc(db,'orders',o._docId||o.id);
      return tx.get(ref).then(function(s){
        if(!s.exists()) throw new Error('That order no longer exists.');
        var cur=s.data();
        if(cur.driverId) throw new Error('Another driver already has that order.');
        tx.update(ref,{
          driverId:d.id,driverName:d.name,driverPhone:d.phone,
          status:OrderStatus.PENDING===cur.status?OrderStatus.CONFIRMED:cur.status,
          assignedBy:auth.currentUser?auth.currentUser.email:'admin',
          assignedAt:serverTimestamp(),acceptedAt:serverTimestamp(),updatedAt:serverTimestamp()
        });
      });
    }).then(function(){ toast('success',d.name+' assigned to '+shortId(o.id)+'.'); })
      .catch(function(e){ toast('error',e.message,'Could not assign'); });
  };
  openModal('modal-confirm');
}

// ── DV-5: review a pending driver's uploaded credentials ──────────────
var DRIVER_DOC_LABELS={licence:'Driver\'s licence',vehicle:'Vehicle photo',insurance:'Insurance',registration:'Vehicle registration'};
function reviewDriverDocs(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  $('sp-sub').textContent='Document review';
  $('sp-title').textContent=d.name;
  var head='<div class="sp-sec"><div class="sp-sec-title">Applicant</div>'+
    row('Vehicle',esc(d.vtype)+' • '+esc(d.plate))+
    row('Phone','<span class="num">'+esc(phoneFmt(d.phone))+'</span>')+
    row('Licence No.','<span class="num">'+esc(d.dlicence)+'</span>')+'</div>';
  var decision='<div class="sp-sec"><div class="sp-sec-title">Decision</div>'+
    '<div class="m-actions" style="justify-content:flex-start">'+
      '<button class="btn btn-success" data-action="approve-driver" data-id="'+esc(d.id)+'">'+icon('check')+'Approve driver</button>'+
      '<button class="btn btn-danger" data-action="reject-driver" data-id="'+esc(d.id)+'">'+icon('close')+'Reject</button>'+
    '</div></div>';
  $('sp-body').innerHTML=head+
    '<div class="sp-sec"><div class="sp-sec-title">Uploaded documents</div>'+
    '<div class="empty-copy" id="doc-review-slot">Loading documents…</div></div>'+decision;
  openSidePanel();
  // Documents live in the private subdoc (drivers/{uid}/private/identity), not
  // on the world-readable parent — same rule as the licence number.
  getDoc(doc(db,'drivers',id,'private','identity')).then(function(s){
    var slot=$('doc-review-slot'); if(!slot) return;
    var docs=s.exists()?(s.data().documents||null):null;
    if(docs&&typeof docs==='object'&&Object.keys(docs).length){
      slot.outerHTML=Object.keys(docs).map(function(k){
        var url=docs[k]; if(!url) return '';
        return '<div class="doc-view"><div class="doc-view-lbl">'+esc(DRIVER_DOC_LABELS[k]||k)+'</div>'+
          '<a href="'+esc(url)+'" target="_blank" rel="noopener"><img src="'+esc(url)+'" alt="'+esc(DRIVER_DOC_LABELS[k]||k)+'" loading="lazy"/></a></div>';
      }).join('');
    }else{
      slot.textContent='This driver registered before in-app document upload existed, so there is nothing to view here. Verify the licence number against a physical or emailed copy before approving.';
    }
  }).catch(function(){
    var slot=$('doc-review-slot'); if(slot) slot.textContent='Could not load the documents for this driver.';
  });
}
function openDriverPanel(id){
  var d=drivers.find(function(x){ return x.id===id; }); if(!d) return;
  $('sp-sub').textContent='Driver Profile';
  $('sp-title').textContent=d.name;
  var recent=orders.filter(function(o){ return d.id&&o.driverId===d.id; });
  if(!recent.length) recent=orders.filter(function(o){ return o.driver===d.name; });
  var recentHtml=recent.slice(0,5).map(function(o){
    return '<div class="sp-row"><span class="sp-lbl">'+esc(o.id)+' — '+esc(o.merchant)+'</span>'+
      '<span class="sp-val">'+badge(o.status)+'</span></div>';
  }).join('')||'<div class="empty-copy">No deliveries recorded yet.</div>';

  // Rating breakdown — real aggregates only. No synthesised distribution.
  var rh;
  var rc=d.ratingCounts;
  if(rc&&typeof rc==='object'){
    var total=[1,2,3,4,5].reduce(function(s,k){ return s+(Number(rc[k])||0); },0);
    if(total>0){
      rh=[5,4,3,2,1].map(function(s){
        var n=Number(rc[s])||0, pct=Math.round((n/total)*100);
        return '<div class="rbar-row"><span class="rbar-lbl">'+s+'</span>'+
          '<div class="rbar-t"><div class="rbar-f" data-w="'+pct+'"></div></div>'+
          '<span class="rbar-pct">'+pct+'%</span></div>';
      }).join('')+'<div class="sc-sub" style="margin-top:8px">Based on '+total+' rating'+(total===1?'':'s')+'.</div>';
    }
  }
  if(!rh) rh='<div class="empty-copy">No per-star rating data recorded yet — only the average ('+
    (Number(d.rating)||0).toFixed(1)+') is available.</div>';

  $('sp-body').innerHTML=
    '<div class="sp-hero"><div class="sp-avatar">'+esc((d.name[0]||'?').toUpperCase())+'</div>'+
      '<div><div class="sp-hero-name">'+esc(d.name)+'</div><div style="margin-top:5px">'+badge(d.status)+'</div></div></div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Contact</div>'+
      row('Phone','<span class="num">'+esc(phoneFmt(d.phone))+'</span>')+
      row('Email','<span class="sp-val sm">'+esc(d.email)+'</span>',true)+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Vehicle</div>'+
      row('Type',esc(d.vtype))+row('Model',esc(d.vehicle))+
      row('Plate','<span class="num">'+esc(d.plate)+'</span>')+
      row('Licence No.','<span class="num">'+esc(d.dlicence)+'</span>')+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Performance</div>'+
      '<div class="sp-row"><span class="sp-lbl">Total Trips</span><span class="sp-val money">'+d.trips+'</span></div>'+
      row('Avg Rating',driverStars(d),false)+
      row('Account',badge(d.rawStatus))+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Rating Breakdown</div>'+rh+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Recent Deliveries</div>'+recentHtml+'</div>';
  openSidePanel();
  animateBars();
}
/** Bars render at width 0 then transition — gives the fill its motion. */
function animateBars(){
  requestAnimationFrame(function(){
    document.querySelectorAll('.rbar-f[data-w],.zf[data-w],.pfill[data-w]').forEach(function(b){
      b.style.width=b.getAttribute('data-w')+'%';
    });
  });
}

// ══════════════════════ CUSTOMERS (P5-05) ══════════════════════
/* The `users` collection had no admin surface at all. An admin looking at an
   order could see a name and go no further — no history, no addresses, no
   lifetime value, and no way to stop an account abusing the service.

   Everything here is derived from the orders already streamed for the Orders
   page rather than re-queried per customer: the panel opens instantly, and a
   customer's figures cannot disagree with the order table they came from. */
function customerOrders(uid){
  return orders.filter(function(o){ return o.customerId===uid; });
}

/* CU-4: the fixed tag catalogue. Slugs are stored; labels + tones are display.
   Kept small and operator-assigned — deriving "VIP" from spend is a different
   feature (and a judgement call the operator should keep). */
var CUSTOMER_TAGS=[
  {slug:'diaspora',      label:'Diaspora',      tone:'info'},
  {slug:'st_thomas',     label:'St. Thomas',    tone:'info'},
  {slug:'business',      label:'Business',      tone:'brand'},
  {slug:'vip',           label:'VIP',           tone:'warning'},
  {slug:'frequent_buyer',label:'Frequent Buyer',tone:'success'},
  {slug:'new_customer',  label:'New Customer',  tone:'neutral'}
];
function tagLabel(slug){ var t=CUSTOMER_TAGS.find(function(x){ return x.slug===slug; }); return t?t.label:slug; }
function tagTone(slug){ var t=CUSTOMER_TAGS.find(function(x){ return x.slug===slug; }); return t?t.tone:'neutral'; }
function customerTagBadges(tags){
  if(!tags||!tags.length) return '';
  return tags.map(function(s){
    return '<span class="bdg bg-'+tagTone(s)+' plain sm">'+esc(tagLabel(s))+'</span>';
  }).join(' ');
}

/* CU-3: the most recent order date for a customer, or null. */
function customerLastOrder(uid){
  var d=null;
  customerOrders(uid).forEach(function(o){
    if(o._ts&&(!d||o._ts>d)) d=o._ts;
  });
  return d;
}

// CU-2: business-rule thresholds. Documented defaults — confirm with the client.
var REPEAT_ORDER_THRESHOLD=2;      // delivered orders to count as a repeat customer
var INACTIVE_DAYS_THRESHOLD=60;    // days without an order to count as inactive

function customerValue(uid){
  // Delivered only. Counting pending or cancelled orders as "lifetime value"
  // inflates it with money that was never collected — and cancellation is now
  // something customers can do themselves (P5-03), so that number would move.
  return customerOrders(uid).reduce(function(sum,o){
    return isDeliveredStatus(o.status)&&o.rawTotal!=null?sum+o.rawTotal:sum;
  },0);
}
function renderCustomers(){
  var tbody=$('customers-tbody'); if(!tbody) return;
  if(!loadedOnce.customers){ tbody.innerHTML=skeletonRows(9,6); return; }
  var q=customerSearch.toLowerCase();
  var rows=customers.filter(function(c){
    return !q||c.name.toLowerCase().includes(q)||c.email.toLowerCase().includes(q)||
      c.phone.toLowerCase().includes(q)||c.id.toLowerCase().includes(q);
  }).sort(function(a,b){
    // Newest first, but accounts with no createdAt (everyone from before
    // Phase 1) sort last rather than being dropped or floated to the top.
    if(!a.joined&&!b.joined) return a.name.localeCompare(b.name);
    if(!a.joined) return 1;
    if(!b.joined) return -1;
    return b.joined-a.joined;
  });

  var stats=$('customers-stats');
  if(stats){
    var now=new Date();
    var monthStart=new Date(now.getFullYear(),now.getMonth(),1).getTime();
    var inactiveCutoff=now.getTime()-INACTIVE_DAYS_THRESHOLD*86400000;
    var disabledCount=customers.filter(function(c){ return c.disabled; }).length;
    var ordering=customers.filter(function(c){ return customerOrders(c.id).length>0; }).length;
    // CU-2: new this month / repeat / inactive / total spend.
    var newThisMonth=customers.filter(function(c){ return c.joined&&c.joined.getTime()>=monthStart; }).length;
    var repeat=customers.filter(function(c){
      return customerOrders(c.id).filter(function(o){ return isDeliveredStatus(o.status); }).length>=REPEAT_ORDER_THRESHOLD;
    }).length;
    var inactive=customers.filter(function(c){
      var last=customerLastOrder(c.id);
      return customerOrders(c.id).length>0&&(!last||last.getTime()<inactiveCutoff);
    }).length;
    var totalSpend=customers.reduce(function(s,c){ return s+customerValue(c.id); },0);
    stats.innerHTML=
      statCard('users','Total Customers',customers.length,'','')+
      statCard('orders','Customers Who Ordered',ordering,customers.length?Math.round((ordering/customers.length)*100)+'% of accounts':'','ocean')+
      statCard('bolt','New This Month',newThisMonth,'joined since the 1st','success')+
      statCard('star','Repeat Customers',repeat,REPEAT_ORDER_THRESHOLD+'+ delivered orders','gold')+
      statCard('clock','Inactive Customers',inactive,'no order in '+INACTIVE_DAYS_THRESHOLD+' days','')+
      statCard('revenue','Total Customer Spend',money(totalSpend),'lifetime delivered','gold')+
      statCard('close','Disabled',disabledCount,disabledCount?'blocked from signing in':'','');
  }

  // Honest cap notice: the listener mirrors at most CUSTOMERS_LIMIT accounts, so
  // once that many are loaded there may be more that this page — and its search,
  // which filters the loaded set — cannot see.
  var capEl=$('customers-cap');
  if(capEl){
    capEl.innerHTML=(customers.length>=CUSTOMERS_LIMIT)
      ? '<div class="notice"><svg class="ic" aria-hidden="true"><use href="#i-warning"/></svg>'
        +'<div>Showing the first '+CUSTOMERS_LIMIT+' customers. Search filters only these — some accounts may not appear until a server-side customer search is added.</div></div>'
      : '';
  }

  if(!rows.length){
    tbody.innerHTML=customerSearch
      ? emptyRow(9,'search','No matching customers','Nothing matched “'+esc(customerSearch)+'”. Try a name, email or phone number.')
      : emptyRow(9,'users','No customers yet','Accounts appear here as soon as somebody registers in the app.');
    return;
  }
  tbody.innerHTML=rows.map(function(c){
    var count=customerOrders(c.id).length;
    var last=customerLastOrder(c.id);   // CU-3
    return '<tr class="row-click'+(c.disabled?' row-muted':'')+'" data-action="view-customer" data-cid="'+esc(c.id)+'">'+
      '<td><b>'+esc(c.name)+'</b></td>'+
      '<td class="cell-mute">'+esc(c.email)+'</td>'+
      '<td class="cell-mute num">'+esc(phoneFmt(c.phone))+'</td>'+
      '<td class="right cell-id">'+count+'</td>'+
      '<td class="cell-mute num">'+(last?esc(last.toLocaleDateString('en-JM',{month:'short',day:'numeric',year:'numeric'})):'—')+'</td>'+
      '<td class="right cell-strong">'+money(customerValue(c.id))+'</td>'+
      '<td>'+(customerTagBadges(c.tags)||'<span class="cell-mute sm">—</span>')+'</td>'+
      '<td>'+(c.disabled
        ?'<span class="bdg bg-danger plain">Disabled'+(c.disabledReason?' — '+esc(c.disabledReason):'')+'</span>'
        :'<span class="bdg bg-success plain">Active</span>')+'</td>'+
      '<td><button class="aicon ai-v" data-action="view-customer" data-cid="'+esc(c.id)+'" title="View customer" aria-label="View customer">'+icon('view')+'</button></td>'+
    '</tr>';
  }).join('');
}
function openCustomerPanel(uid){
  var c=customers.find(function(x){ return x.id===uid; }); if(!c) return;
  panelCustomerId=uid;
  $('sp-sub').textContent='Customer';
  $('sp-title').textContent=c.name;

  var hist=customerOrders(uid).slice(0,10);
  var histHtml=hist.length?hist.map(function(o){
    return '<div class="sp-row"><span class="sp-lbl">'+esc(o.id)+typeBadge(o.type)+'</span>'+
      '<span class="sp-val num">'+esc(o.amount)+' · '+badge(o.status)+'</span></div>';
  }).join(''):'<div class="empty-copy">This customer has not placed an order yet.</div>';

  var delivered=customerOrders(uid).filter(function(o){ return isDeliveredStatus(o.status); }).length;
  var cancelled=customerOrders(uid).filter(function(o){ return isCancelledStatus(o.status); }).length;
  var last=customerLastOrder(uid);      // CU-3
  var waDigits=phoneDial(c.phone).replace(/\D/g,'');

  $('sp-body').innerHTML=
    '<div class="sp-hero"><div class="sp-avatar">'+esc((c.name[0]||'?').toUpperCase())+'</div>'+
      '<div><div class="sp-hero-name">'+esc(c.name)+'</div><div style="margin-top:5px">'+
      (c.disabled
        ?'<span class="bdg bg-danger plain">Disabled'+(c.disabledReason?' — '+esc(c.disabledReason):'')+'</span>'
        :'<span class="bdg bg-success plain">Active</span>')+
      '</div></div></div>'+
    // CU-5: quick actions.
    '<div class="promo-acts" style="margin-bottom:14px">'+
      (c.phone&&c.phone!=='—'?'<a class="pa-btn" href="tel:'+esc(phoneDial(c.phone))+'">Call</a>':'')+
      (waDigits?'<a class="pa-btn" href="https://wa.me/'+esc(waDigits)+'" target="_blank" rel="noopener">WhatsApp</a>':'')+
      '<button class="pa-btn" data-action="customer-orders" data-cid="'+esc(c.id)+'">View orders</button>'+
      '<button class="pa-btn" data-action="customer-notify" data-cid="'+esc(c.id)+'">Send notification</button>'+
    '</div>'+
    (c.disabled&&c.disabledReason
      ?'<div class="sp-sec"><div class="sp-sec-title">Why this account is disabled</div>'+
        '<div class="empty-copy">'+esc(c.disabledReason)+'</div></div>':'')+
    // CU-4: segment tags.
    '<div class="sp-sec"><div class="sp-sec-title">Tags '+
      '<button class="pa-btn" data-action="customer-tags" data-cid="'+esc(c.id)+'" style="float:right;font-weight:600">Edit</button></div>'+
      '<div>'+(customerTagBadges(c.tags)||'<span class="empty-copy">No tags. Use Edit to add Diaspora, VIP, Business…</span>')+'</div></div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Contact</div>'+
      row('Email','<span class="sp-val sm">'+esc(c.email)+'</span>',true)+
      row('Phone','<span class="num">'+esc(phoneFmt(c.phone))+'</span>')+
      row('Joined',esc(c.joined?c.joined.toLocaleDateString('en-JM',{year:'numeric',month:'short',day:'numeric'}):'Before records began'))+
      row('Last order',esc(last?last.toLocaleDateString('en-JM',{year:'numeric',month:'short',day:'numeric'}):'Never'))+
      row('Push',c.hasPush?'Registered':'No device registered')+
      row('User ID','<span class="sp-val sm num">'+esc(c.id)+'</span>',true)+
    '</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Value</div>'+
      '<div class="sp-row"><span class="sp-lbl">Lifetime (delivered)</span><span class="sp-val money">'+money(customerValue(uid))+'</span></div>'+
      row('Orders delivered',String(delivered))+
      row('Orders cancelled',String(cancelled))+
    '</div>'+
    // Addresses are a subcollection, so they are not in the streamed mirror.
    // Loaded on demand, which is also the only time an admin needs them.
    '<div class="sp-sec"><div class="sp-sec-title">Saved Addresses</div>'+
      '<div id="cust-addresses"><div class="empty-copy">Loading…</div></div></div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Recent Orders</div>'+histHtml+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Account</div>'+
      '<button class="btn '+(c.disabled?'btn-secondary':'btn-danger')+' btn-block" '+
        'data-action="toggle-customer" data-cid="'+esc(c.id)+'">'+
        icon(c.disabled?'check':'close')+(c.disabled?'Re-enable account':'Disable account')+'</button>'+
      '<div class="sc-sub" style="margin-top:8px">Disabling signs the customer out '+
        'immediately and blocks them from signing in again.</div>'+
    '</div>';
  openSidePanel();
  loadCustomerAddresses(uid);
}
function loadCustomerAddresses(uid){
  getDocs(collection(db,'users',uid,'addresses')).then(function(snap){
    // The panel may have been closed or switched while this was in flight.
    if(panelCustomerId!==uid) return;
    var el=$('cust-addresses'); if(!el) return;
    if(snap.empty){ el.innerHTML='<div class="empty-copy">No saved addresses.</div>'; return; }
    el.innerHTML=snap.docs.map(function(d){
      var a=d.data();
      return row(esc(a.label||'Address'),'<span class="sp-val sm">'+esc(a.text||'—')+'</span>',true);
    }).join('');
  }).catch(function(e){
    if(panelCustomerId!==uid) return;
    var el=$('cust-addresses'); if(!el) return;
    // A failure here must not read as "this customer has no addresses".
    el.innerHTML='<div class="empty-copy">Could not load addresses: '+esc(e.message)+'</div>';
  });
}
// ── CU-4: tag assignment ──────────────────────────────────────────────
function editCustomerTags(uid){
  var c=customers.find(function(x){ return x.id===uid; }); if(!c) return;
  var have={}; (c.tags||[]).forEach(function(s){ have[s]=1; });
  $('cf-ico').className='m-ico'; $('cf-ico').innerHTML=icon('users','ic-lg');
  $('cf-title').textContent='Tags for '+c.name;
  $('cf-body').innerHTML='<div class="tag-picker">'+CUSTOMER_TAGS.map(function(t){
    return '<label class="tag-opt"><input type="checkbox" value="'+esc(t.slug)+'"'+(have[t.slug]?' checked':'')+'>'+
      '<span class="bdg bg-'+t.tone+' plain sm">'+esc(t.label)+'</span></label>';
  }).join('')+'</div>';
  var ok=$('cf-ok'); ok.textContent='Save tags'; ok.className='btn btn-primary';
  confirmResolve=function(confirmed){
    var picked=Array.prototype.slice.call(document.querySelectorAll('.tag-picker input:checked'))
      .map(function(i){ return i.value; });
    $('cf-body').innerHTML='';
    if(!confirmed) return;
    updateDoc(doc(db,'users',uid),{
      tags:picked,
      tagsUpdatedAt:serverTimestamp(),
      tagsUpdatedBy:auth.currentUser?auth.currentUser.uid:''
    }).then(function(){
      toast('success','Tags updated for '+c.name+'.');
      if(panelCustomerId===uid) setTimeout(function(){ openCustomerPanel(uid); },250);
    }).catch(function(e){ toast('error',e.message,'Could not save tags'); });
  };
  openModal('modal-confirm');
}
// ── CU-5: jump to this customer's orders / notify them ────────────────
function viewCustomerOrders(uid){
  var c=customers.find(function(x){ return x.id===uid; }); if(!c) return;
  closeSidePanel();
  navTo('orders');
  clearOrderFilters();
  ordersFilter='All'; updateOrdersTabs();
  var s=$('orders-search'); if(s){ s.value=c.name; }
  renderOrders();
  toast('info','Showing orders matching “'+c.name+'”.');
}
function notifyCustomer(uid){
  var c=customers.find(function(x){ return x.id===uid; }); if(!c) return;
  closeSidePanel();
  navTo('notifications');
  // Per-customer targeting is NT-2 (audience segments). Until then the operator
  // composes a message and picks the audience by hand; drop a hint.
  toast('info','Compose the message, then choose the audience. Per-customer sending arrives with audience targeting (NT-2).');
}

var setUserDisabled=httpsCallable(fns,'setUserDisabled');
/* Goes through a callable, not a document write.
   `users/{uid}.disabled` is a flag Firestore rules never consult, so setting it
   from here would stop nobody: the customer keeps their session and keeps
   ordering. The function disables the Auth account and revokes refresh tokens,
   then records the flag — so the panel and reality agree. */
function toggleCustomerDisabled(uid){
  var c=customers.find(function(x){ return x.id===uid; }); if(!c) return;

  if(c.disabled){
    confirmDialog({title:'Re-enable this account?',
      body:'“'+c.name+'” will be able to sign in and place orders again.',
      confirmLabel:'Re-enable'})
      .then(function(ok){ if(ok) applyCustomerDisabled(uid,false,''); });
    return;
  }

  // A reason is required when taking access away. An audit trail that says
  // only "an admin did this" answers none of the questions asked later.
  // CU-6: a fixed set of reasons, not free text — so the badge can read
  // "Disabled — Payment issue" and the reasons stay consistent across accounts.
  $('cf-ico').className='m-ico danger';
  $('cf-ico').innerHTML=icon('close','ic-lg');
  $('cf-title').textContent='Disable '+c.name+'?';
  $('cf-body').innerHTML='They will be signed out immediately and cannot sign in again '+
    'until re-enabled. Their past orders are kept.'+
    '<label for="cf-reason" style="display:block;margin-top:12px;font-size:13px">Reason (required)</label>'+
    '<select id="cf-reason" style="width:100%;margin-top:6px">'+
      '<option value="">Select a reason…</option>'+
      DISABLE_REASONS.map(function(r){ return '<option value="'+esc(r)+'">'+esc(r)+'</option>'; }).join('')+
    '</select>';
  var ok=$('cf-ok'); ok.textContent='Disable account'; ok.className='btn btn-danger';
  confirmResolve=function(confirmed){
    var reason=(($('cf-reason')||{}).value||'').trim();
    $('cf-body').innerHTML='';
    if(!confirmed) return;
    if(!reason){ toast('warning','Choose a reason — it is recorded against the account.'); return; }
    applyCustomerDisabled(uid,true,reason);
  };
  openModal('modal-confirm');
}
/* CU-6: canned disable reasons. The badge shows "Disabled — <reason>". */
var DISABLE_REASONS=['Fraud review','Customer request','Payment issue'];
function applyCustomerDisabled(uid,disabled,reason){
  setUserDisabled({uid:uid,disabled:disabled,reason:reason})
    .then(function(){
      toast('success',disabled?'Account disabled.':'Account re-enabled.');
      // The users listener refreshes the row; reopen so the panel matches.
      if(panelCustomerId===uid) setTimeout(function(){ openCustomerPanel(uid); },300);
    })
    .catch(function(e){
      /* Same trap as "Could not add driver / internal": Cloud Functions is a
         Blaze product and this project is on Spark, so the callable does not
         exist and the client SDK reports the unparseable 404 as code 'internal'
         with the message 'internal'. Say which of the two it is, because the
         fix is completely different. */
      var msg=(e&&e.code==='functions/internal')||/^internal$/i.test((e&&e.message)||'')
        ? 'This needs the setUserDisabled Cloud Function, which is not deployed — Cloud Functions requires the Blaze plan. '+
          'Until then an account can only be disabled from Firebase Console → Authentication.'
        : e.message;
      toast('error',msg,'Could not change the account');
    });
}

// ══════════════════════ OVERSEAS ENQUIRIES ══════════════════════
/* The other half of the customer app's shop-and-deliver form. A status an
   operator moves here is shown to the customer in the app, which is the only
   reason moving it is worth anything: somebody is waiting to hear back.

   Filtering, searching and sorting all live in overseas-status.js so they are
   testable in Node; this file does the painting. */

function inquiryBadge(s){
  var st=Overseas.normalise(s);
  return '<span class="bdg bg-'+Overseas.TONE[st]+'">'+esc(Overseas.LABEL[st])+'</span>';
}
function inquiryBudget(b){
  // Optional free text on the form — "J$10,000", "US$70", or nothing at all.
  // Blank means "spend what it takes" and must not render as an empty cell.
  return b?String(b):'—';
}
function inquiryRef(id){ return String(id||'').slice(0,6).toUpperCase(); }

function renderOverseasTabs(){
  var tabs=$('overseas-tabs'); if(!tabs) return;
  var s=Overseas.summarise(inquiries);
  // SD-4: twelve statuses is too many tabs. Group into the buckets an operator
  // actually works from, plus a jump to each awaiting/in-progress stage.
  var defs=[
    {k:'open',lbl:'Open',n:s.open},
    {k:Overseas.NEW,lbl:'New',n:s.counts[Overseas.NEW]},
    {k:Overseas.AWAITING_CUSTOMER,lbl:'Awaiting Customer',n:s.counts[Overseas.AWAITING_CUSTOMER]},
    {k:Overseas.SHOPPING,lbl:'Shopping',n:s.counts[Overseas.SHOPPING]},
    {k:Overseas.OUT_FOR_DELIVERY,lbl:'Out for Delivery',n:s.counts[Overseas.OUT_FOR_DELIVERY]},
    {k:'closed',lbl:'Closed',n:s.closed},
    {k:'all',lbl:'All',n:s.total}
  ];
  tabs.innerHTML=defs.map(function(d){
    return '<div class="tab'+(overseasFilter===d.k?' active':'')+'" data-otab="'+d.k+'" role="tab" tabindex="0">'+
      esc(d.lbl)+' <b class="num">'+d.n+'</b></div>';
  }).join('');
}
function renderOverseas(){
  renderOverseasTabs();
  var tbody=$('overseas-tbody'); if(!tbody) return;
  if(!loadedOnce.overseas){ tbody.innerHTML=skeletonRows(9,5); return; }

  var stats=$('overseas-stats');
  if(stats){
    var s=Overseas.summarise(inquiries);
    // Client checklist SD-2 / SD-3 / SD-3b. With the SD-4 vocabulary the
    // figures are now exact: New = genuinely new (awaiting first review),
    // Awaiting Customer = a quote is out and we are waiting on them, Closed =
    // every terminal state (completed / declined / cancelled / expired).
    stats.innerHTML=
      statCard('send','New Requests',s.newCount,'awaiting review','')+
      statCard('clock','Awaiting Customer',s.awaitingCustomer,'quote sent, waiting for response','gold')+
      statCard('success','Closed',s.closed,s.counts[Overseas.COMPLETED]+' completed · '+s.counts[Overseas.DECLINED]+' declined','success');
  }

  var rows=Overseas.filterInquiries(inquiries,{status:overseasFilter,q:overseasSearch});
  if(!rows.length){
    tbody.innerHTML=overseasSearch
      ? emptyRow(9,'search','No matching enquiries','Nothing matched “'+esc(overseasSearch)+'”. Try a name, parish or phone number.')
      : emptyRow(9,'box','No open requests','New Shop & Deliver requests will appear here.');
    return;
  }
  tbody.innerHTML=rows.map(function(i){
    // SD-5: item count + requested store, at a glance.
    var n=Overseas.itemCount(i.itemDescription);
    var listCell=esc(i.itemCategory)+' · '+n+' item'+(n===1?'':'s')+
      (i.requestedStore?' · <span class="cell-mute">'+esc(i.requestedStore)+'</span>':'');
    var st=Overseas.normalise(i.status);
    // SD-6: Review | Quote Customer | Call | WhatsApp, right on the row.
    var acts='<div class="promo-acts">'+
      '<button class="pa-btn" data-action="view-inquiry" data-iid="'+esc(i.id)+'">Review</button>';
    if(st===Overseas.NEW||st===Overseas.REVIEWING)
      acts+='<button class="pa-btn" data-action="inq-quote" data-iid="'+esc(i.id)+'">Quote customer</button>';
    if(i.contactPhone){
      acts+='<a class="pa-btn" href="tel:'+esc(phoneDial(i.contactPhone))+'">Call</a>'+
        '<a class="pa-btn" href="https://wa.me/'+esc(phoneDial(i.contactPhone).replace(/\D/g,''))+'" target="_blank" rel="noopener">WhatsApp</a>';
    }
    acts+='</div>';
    return '<tr>'+
      '<td><span class="cell-id">'+esc(inquiryRef(i.id))+'</span></td>'+
      '<td><b>'+esc(i.customerName)+'</b><div class="cell-mute">'+esc(i.originCountry)+'</div></td>'+
      '<td>'+esc(i.recipientName)+'</td>'+
      '<td class="cell-mute">'+esc(i.recipientParish)+'</td>'+
      '<td class="cell-mute">'+listCell+'</td>'+
      '<td class="right num">'+esc(inquiryBudget(i.budget))+'</td>'+
      '<td>'+inquiryBadge(i.status)+'</td>'+
      // A brand-new enquiry has no resolved timestamp yet, and "—" would read
      // as missing data rather than "seconds ago".
      '<td class="cell-mute num">'+esc(i.createdAt?fmtStamp(i.createdAt):'Just now')+'</td>'+
      '<td>'+acts+'</td>'+
    '</tr>';
  }).join('');
}

function openInquiryPanel(id){
  var i=inquiries.find(function(x){ return x.id===id; }); if(!i) return;
  panelInquiryId=id;
  $('sp-sub').textContent='Shop & Deliver';
  $('sp-title').textContent='#'+inquiryRef(i.id);

  /* mailto: and tel: rather than a copy button. Replying is the entire job of
     this page, and the reply happens in the operator's mail client — the panel
     should hand them the draft, not the address to retype. */
  var subject=encodeURIComponent('Your ShipEast shopping request #'+inquiryRef(i.id));
  var contactHtml=
    row('Name',esc(i.customerName))+
    row('Email',i.contactEmail
      ?'<a class="sp-val sm" href="mailto:'+esc(i.contactEmail)+'?subject='+subject+'">'+esc(i.contactEmail)+'</a>'
      :'—',true)+
    row('Phone',i.contactPhone
      ?'<a class="sp-val num" href="tel:'+esc(phoneDial(i.contactPhone))+'">'+esc(phoneFmt(i.contactPhone))+'</a>'
      :'—')+
    row('Based in',esc(i.originCountry));

  var recipientHtml=
    row('Recipient',esc(i.recipientName))+
    row('Phone',i.recipientPhone
      ?'<a class="sp-val num" href="tel:'+esc(phoneDial(i.recipientPhone))+'">'+esc(phoneFmt(i.recipientPhone))+'</a>'
      :'—')+
    row('Address','<span class="sp-val sm">'+esc(i.recipientAddress)+'</span>',true)+
    row('Parish',esc(i.recipientParish));

  var itemN=Overseas.itemCount(i.itemDescription);
  var shoppingHtml=
    row('Category',esc(i.itemCategory))+
    row('Requested store',esc(i.requestedStore||'Any store'))+
    row('Budget','<span class="num">'+esc(inquiryBudget(i.budget))+'</span>')+
    '<div class="sp-row"><span class="sp-lbl">Shopping list — '+itemN+' item'+(itemN===1?'':'s')+'</span></div>'+
    '<div class="empty-copy" style="max-width:none;white-space:pre-wrap">'+esc(i.itemDescription)+'</div>'+
    (i.notes?'<div class="sp-row"><span class="sp-lbl">Customer notes</span></div>'+
      '<div class="empty-copy" style="max-width:none">'+esc(i.notes)+'</div>':'');

  var handledHtml=
    row('Received',esc(i.createdAt?fmtStamp(i.createdAt):'Just now'))+
    (i.updatedAt?row('Last updated',esc(fmtStamp(i.updatedAt))):'')+
    (i.handledBy?row('Handled by','<span class="sp-val sm num">'+esc(i.handledBy)+'</span>',true):'');

  var options=[i.status].concat(Overseas.nextStatuses(i.status)).map(function(st){
    return '<option value="'+st+'"'+(st===i.status?' selected':'')+'>'+esc(Overseas.LABEL[st])+'</option>';
  }).join('');

  // SD-7: the quote. `quoteTotal` is derived from the three parts on save, so
  // there is nothing to keep in sync.
  var payOpts=['','pending','paid','refunded','waived'].map(function(p){
    return '<option value="'+p+'"'+(p===i.quotePaymentStatus?' selected':'')+'>'+
      (p?esc(p.charAt(0).toUpperCase()+p.slice(1)):'Not set')+'</option>';
  }).join('');
  var quoteExpVal=i.quoteExpiresAt?isoDate(i.quoteExpiresAt):'';
  var quoteSummary=i.quoteTotal!=null
    ? '<div class="sp-row"><span class="sp-lbl">Current quote</span><span class="sp-val money">'+money(i.quoteTotal)+
      (i.quoteExpiresAt?' <span class="cell-mute sm">exp. '+esc(i.quoteExpiresAt.toLocaleDateString('en-JM',{month:'short',day:'numeric'}))+'</span>':'')+'</span></div>'
    : '<div class="empty-copy">No quote sent yet.</div>';
  var quoteHtml=quoteSummary+
    '<div class="fr"><label for="q-items">Estimated item cost (J$)</label><input id="q-items" type="number" min="0" step="1" value="'+(i.quoteItemsCost!=null?i.quoteItemsCost:'')+'"/></div>'+
    '<div class="fr"><label for="q-service">Shopping / service fee (J$)</label><input id="q-service" type="number" min="0" step="1" value="'+(i.quoteServiceFee!=null?i.quoteServiceFee:'')+'"/></div>'+
    '<div class="fr"><label for="q-delivery">Delivery fee (J$)</label><input id="q-delivery" type="number" min="0" step="1" value="'+(i.quoteDeliveryFee!=null?i.quoteDeliveryFee:'')+'"/></div>'+
    '<div class="sp-row"><span class="sp-lbl">Total quote</span><span class="sp-val money num" id="q-total">'+money(i.quoteTotal||0)+'</span></div>'+
    '<div class="fr"><label for="q-expiry">Quote expires</label><input id="q-expiry" type="date" value="'+quoteExpVal+'"/></div>'+
    '<div class="fr"><label for="q-pay">Payment status</label><select id="q-pay">'+payOpts+'</select></div>'+
    '<button class="btn btn-outline btn-block" data-action="save-quote" data-iid="'+esc(i.id)+'">'+icon('receipt')+'Save quote</button>';

  $('sp-body').innerHTML=
    '<div class="sp-sec"><div class="sp-sec-title">Status</div>'+
      '<div class="sp-row"><span class="sp-lbl">Now</span><span class="sp-val">'+inquiryBadge(i.status)+'</span></div>'+
    '</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Customer</div>'+contactHtml+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Delivering To</div>'+recipientHtml+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Shopping</div>'+shoppingHtml+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Quote</div>'+quoteHtml+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Handling</div>'+handledHtml+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Update</div>'+
      '<div class="fr"><label for="sp-inq-status">Status</label>'+
        '<select id="sp-inq-status">'+options+'</select></div>'+
      // Internal: the customer never sees this, which is exactly why it needs
      // saying on the label. An operator who assumes otherwise writes the reply
      // in here and nobody receives it.
      '<div class="fr"><label for="sp-inq-note">Internal note — not shown to the customer</label>'+
        '<textarea id="sp-inq-note" rows="4" maxlength="1000" '+
        'placeholder="Store confirmed, waiting on the total…">'+esc(i.adminNote)+'</textarea></div>'+
      '<button class="btn btn-primary btn-block" data-action="save-inquiry" data-iid="'+esc(i.id)+'">'+
        icon('check')+'Save</button>'+
      '<div class="sc-sub" style="margin-top:8px">The customer sees the status change in '+
        'their app. Reply to them by email — this panel does not send anything.</div>'+
    '</div>';
  openSidePanel();
}

/* SD-7: recompute the quote total from its three parts as the operator types. */
function syncQuoteTotal(){
  var t=$('q-total'); if(!t) return;
  var n=function(id){ return Math.max(0,Math.round(Number(($(id)||{}).value)||0)); };
  t.textContent=money(n('q-items')+n('q-service')+n('q-delivery'));
}
/* SD-7: save the quote sub-fields. `quoteTotal` is derived here so the stored
   total can never disagree with its parts. */
function saveQuote(id){
  var i=inquiries.find(function(x){ return x.id===id; }); if(!i) return;
  var n=function(el){ var v=($(el)||{}).value; return v===''?null:Math.max(0,Math.round(Number(v)||0)); };
  var items=n('q-items'),service=n('q-service'),delivery=n('q-delivery');
  var total=(items||0)+(service||0)+(delivery||0);
  var expRaw=($('q-expiry')||{}).value||'';
  var expiresAt=null;
  if(expRaw){ var d=new Date(expRaw+'T23:59:59'); if(!isNaN(d.getTime())) expiresAt=Timestamp.fromDate(d); }
  updateDoc(doc(db,'overseasInquiries',id),{
    quoteItemsCost:items,quoteServiceFee:service,quoteDeliveryFee:delivery,
    quoteTotal:total,quoteExpiresAt:expiresAt,
    quotePaymentStatus:($('q-pay')||{}).value||'',
    quotedBy:auth.currentUser?auth.currentUser.uid:'',
    quotedAt:serverTimestamp(),updatedAt:serverTimestamp()
  }).then(function(){
    toast('success','Quote saved — J$'+total+'. Email it to '+i.customerName+'.');
    if(panelInquiryId===id) setTimeout(function(){ openInquiryPanel(id); },250);
  }).catch(function(e){ toast('error',e.message,'Could not save quote'); });
}

/* SD-6 one-click "Quote customer" — advances the request to Quote Sent. The
   actual quote goes to the customer by email (this page sends nothing), so the
   toast says so. */
function quoteInquiry(id){
  var i=inquiries.find(function(x){ return x.id===id; }); if(!i) return;
  updateDoc(doc(db,'overseasInquiries',id),{
    status:Overseas.QUOTE_SENT,
    handledBy:auth.currentUser?auth.currentUser.uid:'',
    handledAt:serverTimestamp(),updatedAt:serverTimestamp()
  }).then(function(){ toast('success','Marked Quote Sent. Email the total to '+i.customerName+'.'); })
    .catch(function(e){ toast('error',e.message,'Could not update'); });
}
function saveInquiry(id){
  var i=inquiries.find(function(x){ return x.id===id; }); if(!i) return;
  var status=(($('sp-inq-status')||{}).value||i.status);
  var note=(($('sp-inq-note')||{}).value||'').trim();
  if(status===i.status&&note===i.adminNote){ toast('info','Nothing changed.'); return; }

  /* Exactly the five fields firestore.rules permits an admin to touch. The
     customer's own shopping list is deliberately not among them: it is what we
     shop against, so a wrong list is a new request rather than an edit.
     Sending a sixth field here would fail the whole write. */
  updateDoc(doc(db,'overseasInquiries',id),{
    status:status,
    adminNote:note,
    handledBy:auth.currentUser?auth.currentUser.uid:'',
    handledAt:serverTimestamp(),
    updatedAt:serverTimestamp()
  }).then(function(){
    toast('success','Enquiry updated.');
    // The listener refreshes the row; reopen so the panel agrees with it.
    if(panelInquiryId===id) setTimeout(function(){ openInquiryPanel(id); },250);
  }).catch(function(e){
    toast('error',e.message,'Could not update the enquiry');
  });
}

// ══════════════════════ PRICING (P5-01) ══════════════════════
/* `settings/pricing` was created in Phase 3 for the driver commission rate and
   has only ever been editable from the Firebase console — the undocumented
   console-edit habit this project exists to end.

   It now also holds the package weight bands, and the customer app refuses to
   quote a package price until they exist. So this form is what turns the
   Packages category on, and there is no default table anywhere in the codebase
   that could turn it on by accident. */
var pricingLoaded=false;
function loadPricing(){
  getDoc(doc(db,'settings','pricing')).then(function(snap){
    var s=snap.exists()?snap.data():{};
    if($('pr-bands')) $('pr-bands').value=formatBands(s.packageBands);
    if($('pr-overage')) $('pr-overage').value=s.packageOveragePerKg!=null?s.packageOveragePerKg:'';
    if($('pr-packing')) $('pr-packing').value=s.packingSurcharge!=null?s.packingSurcharge:'';
    if($('pr-maxweight')) $('pr-maxweight').value=s.packageMaxWeightKg!=null?s.packageMaxWeightKg:'';
    if($('pr-commission')) $('pr-commission').value=s.driverCommissionRate!=null?s.driverCommissionRate:'';
    pricingLoaded=true;
    renderPricingPreview();
  }).catch(function(e){
    // Never silently show an empty form over a table that exists — the admin
    // would retype it and could overwrite live prices with a typo.
    toast('error','Could not load pricing: '+e.message);
  });
}
function renderPricingPreview(){
  var el=$('pr-preview'); if(!el) return;
  var parsed=parseBands(($('pr-bands')||{}).value||'');
  if(parsed.errors.length){
    el.innerHTML='<b style="color:var(--danger)">Not saveable yet</b><br>'+
      parsed.errors.map(esc).join('<br>');
    return;
  }
  var lines=describeBands(parsed.bands,parseAmount(($('pr-overage')||{}).value)||0);
  var packing=parseAmount(($('pr-packing')||{}).value);
  el.innerHTML='<b>A customer will be quoted</b><br>'+lines.map(esc).join('<br>')+
    (packing?'<br>Packing adds '+money(packing)+'.':'');
}
function savePricing(){
  var parsed=parseBands(($('pr-bands')||{}).value||'');
  if(parsed.errors.length){
    // Saving a partially-parsed table would price parcels from a list nobody
    // approved. Refuse the whole write.
    toast('error',parsed.errors[0],'Fix the weight bands first');
    return;
  }
  var maxWeight=parseAmount(($('pr-maxweight')||{}).value);
  var rateRaw=(($('pr-commission')||{}).value||'').trim();
  var rate=rateRaw===''?null:Number(rateRaw);
  if(rate!==null&&(!isFinite(rate)||rate<=0||rate>1)){
    toast('error','The commission rate must be between 0 and 1 — 0.1 means 10%.');
    return;
  }

  var payload={
    packageBands:parsed.bands,
    packageOveragePerKg:parseAmount(($('pr-overage')||{}).value)||0,
    packingSurcharge:parseAmount(($('pr-packing')||{}).value)||0,
    updatedAt:serverTimestamp()
  };
  // Only written when given, so clearing the field cannot silently reset the
  // limit or the payout rate to something nobody chose.
  if(maxWeight) payload.packageMaxWeightKg=maxWeight;
  if(rate!==null) payload.driverCommissionRate=rate;

  setDoc(doc(db,'settings','pricing'),payload,{merge:true})
    .then(function(){ toast('success','Pricing saved. Packages are live.'); })
    .catch(function(e){ toast('error',e.message,'Could not save pricing'); });
}

// ══════════════════════ DANGER ZONE — ERASE ALL DATA ══════════════════════
/* A total reset of the operational data, for handing the system to a new
   operator or clearing a test population. It removes every customer, driver,
   order, saved address, notification and overseas enquiry, and nothing else:
   restaurants, menu items, promo codes and the pricing/commission settings
   survive, so the three apps stay usable the moment new users arrive.

   What it deliberately does NOT do: it cannot delete Firebase Auth login
   accounts — that needs the Admin SDK, which this client-only panel has no
   access to. A wiped customer's old email/password still signs in, into a
   fresh empty account. Removing the logins too means deleting them in the
   Firebase console, or deploying a callable on the Blaze plan.

   Two gates guard it: a warning dialog (openWipeFlow) and a type-the-phrase
   modal (this button). Both must be cleared before a single document is
   touched. The corresponding delete permissions live in firestore.rules —
   without them deployed, the users/orders/enquiries sweeps fail. */
var WIPE_PHRASE='ERASE ALL DATA';
var wiping=false;

function openWipeFlow(){
  confirmDialog({
    title:'Danger Zone — erase all data?',
    body:'This permanently deletes ALL customers, drivers, orders, saved addresses, '+
         'notifications and overseas enquiries, across all three apps. Restaurants, '+
         'menus, promo codes and pricing settings are kept. It is irreversible and '+
         'there is no backup.',
    confirmLabel:'I understand — continue'
  }).then(function(ok){
    if(!ok) return;
    var inp=$('wipe-phrase'); if(inp){ inp.value=''; inp.disabled=false; }
    var go=$('wipe-go'); if(go){ go.disabled=true; go.textContent='Permanently erase'; }
    var cancel=$('wipe-cancel'); if(cancel) cancel.disabled=false;
    var pr=$('wipe-progress'); if(pr) pr.textContent='';
    openModal('modal-wipe');
    setTimeout(function(){ if(inp) inp.focus(); },50);
  });
}

// Delete an array of DocumentReferences in batches. Firestore caps a batch at
// 500 writes; 400 leaves headroom and keeps each round trip small.
function wipeCommitBatched(refs){
  var i=0;
  function next(){
    if(i>=refs.length) return Promise.resolve();
    var batch=writeBatch(db);
    refs.slice(i,i+400).forEach(function(r){ batch.delete(r); });
    i+=400;
    return batch.commit().then(next);
  }
  return next();
}

function wipeFlat(coll){
  return getDocs(collection(db,coll)).then(function(snap){
    var refs=snap.docs.map(function(d){ return d.ref; });
    return wipeCommitBatched(refs).then(function(){ return refs.length; });
  });
}

// A parent collection whose docs each own one or more subcollections. Deleting
// the parent does NOT remove them, so each subcollection is swept first, then
// the parents. Runs one parent at a time to keep reads bounded on large sets.
function wipeWithSub(coll,subs){
  return getDocs(collection(db,coll)).then(function(snap){
    var parents=snap.docs, count=0, pi=0;
    function nextParent(){
      if(pi>=parents.length){
        return wipeCommitBatched(parents.map(function(d){ return d.ref; }))
          .then(function(){ return count+parents.length; });
      }
      var d=parents[pi++], si=0;
      function nextSub(){
        if(si>=subs.length) return nextParent();
        return getDocs(collection(db,coll,d.id,subs[si++])).then(function(ss){
          var refs=ss.docs.map(function(x){ return x.ref; });
          count+=refs.length;
          return wipeCommitBatched(refs).then(nextSub);
        });
      }
      return nextSub();
    }
    return nextParent();
  });
}

function runWipe(status){
  var total=0;
  return wipeWithSub('users',['addresses']).then(function(n){
    total+=n; status('Cleared customers and addresses ('+n+'). Clearing drivers…');
    return wipeWithSub('drivers',['private']);
  }).then(function(n){
    total+=n; status('Cleared drivers ('+n+'). Clearing orders…');
    return wipeFlat('orders');
  }).then(function(n){
    total+=n; status('Cleared orders ('+n+'). Clearing notifications…');
    return wipeFlat('notifications');
  }).then(function(n){
    total+=n; status('Cleared notifications ('+n+'). Clearing overseas enquiries…');
    return wipeFlat('overseasInquiries');
  }).then(function(n){
    total+=n; return total;
  });
}

function eraseAllData(){
  if(wiping) return;
  var phrase=(($('wipe-phrase')||{}).value||'').trim();
  if(phrase!==WIPE_PHRASE){ toast('error','Type '+WIPE_PHRASE+' exactly to confirm.'); return; }
  wiping=true;
  var go=$('wipe-go'), cancel=$('wipe-cancel'), inp=$('wipe-phrase'), pr=$('wipe-progress');
  if(go){ go.disabled=true; go.textContent='Erasing…'; }
  if(cancel) cancel.disabled=true;
  if(inp) inp.disabled=true;
  function status(msg){ if(pr) pr.textContent=msg; }
  status('Erasing… do not close this window.');

  runWipe(status).then(function(total){
    closeModal('modal-wipe');
    toast('success',total+' record'+(total===1?'':'s')+' deleted. Customers, drivers, orders, '+
      'addresses, notifications and enquiries are gone.','All data erased');
  }).catch(function(e){
    // A permission-denied here almost always means firestore.rules with the
    // admin-delete clauses has not been deployed yet.
    var hint=/permission/i.test(e.message||'')
      ? 'Permission denied — deploy the updated firestore.rules first.' : e.message;
    status('Stopped: '+hint);
    toast('error',hint,'Erase failed');
  }).finally(function(){
    wiping=false;
    if(go){ go.disabled=false; go.textContent='Permanently erase'; }
    if(cancel) cancel.disabled=false;
    if(inp) inp.disabled=false;
  });
}

// ══════════════════════ MERCHANTS ══════════════════════
function renderMerchantStats(){
  var el=$('merchants-stats'); if(!el) return;
  var openC=merchants.filter(function(m){ return m.open; }).length;
  el.innerHTML=
    statCard('merchants','Total Merchants',merchants.length,'','')+
    statCard('check','Open Now',openC,'Accepting orders','success')+
    statCard('clock','Closed',merchants.length-openC,'Not accepting','gold');
}
function renderMerchants(){
  renderMerchantStats();
  var tbody=$('merchants-tbody'); if(!tbody) return;
  if(!loadedOnce.merchants){ tbody.innerHTML=skeletonRows(9,5); return; }
  if(!merchants.length){
    tbody.innerHTML=emptyRow(9,'store','No merchants yet','Add a restaurant, grocer, or pharmacy to start taking orders.');
    return;
  }
  tbody.innerHTML=merchants.map(function(m){
    return '<tr>'+
      '<td><div class="cell-media">'+merchantMedia(m)+'<b>'+esc(m.name)+'</b></div></td>'+
      '<td><span class="bdg bg-info plain">'+esc(m.category)+'</span></td>'+
      '<td class="cell-mute num">'+esc(phoneFmt(m.phone))+'</td>'+
      '<td class="cell-mute" style="max-width:180px;font-size:12px">'+esc(m.address)+'</td>'+
      '<td class="right cell-id">'+ordersTodayFor(m.id)+'</td>'+
      '<td>'+starsOrNone(m.rating,m.ratingCount)+'</td>'+
      '<td>'+badge(m.open?'Open':'Closed')+'</td>'+
      '<td><label class="tgl" title="Toggle open"><input type="checkbox"'+(m.open?' checked':'')+
        ' class="tgl-merchant" data-id="'+esc(m.id)+'" aria-label="Merchant open"><span class="ts"></span></label></td>'+
      '<td><div class="cell-actions">'+
        '<button class="aicon ai-v" data-action="view-merchant" data-id="'+esc(m.id)+'" title="View" aria-label="View merchant">'+icon('view')+'</button>'+
        '<button class="aicon ai-e" data-action="edit-merchant" data-id="'+esc(m.id)+'" title="Edit" aria-label="Edit merchant">'+icon('edit')+'</button>'+
        '<button class="aicon ai-d" data-action="del-merchant" data-id="'+esc(m.id)+'" title="Delete" aria-label="Delete merchant">'+icon('delete')+'</button>'+
      '</div></td>'+
    '</tr>';
  }).join('');
}
/* ── Merchant cover uploader (P4-01, upload-only, inline) ─────────────
   Built once and re-pointed at whichever merchant is open. `#m-imageurl` is a
   HIDDEN field the uploader writes to via onChange, so `saveMerchant` is
   unchanged. No "paste a URL" path and no Cloud Storage: the photo is compressed
   and stored INLINE in the merchant document as a data URL (see inlineUpload).
   Because no bucket path is needed, the zone works even for a brand-new
   merchant — the photo saves in one step with the rest of the form. */
var merchantUploader=null;
function mountMerchantUploader(){
  if(merchantUploader) return merchantUploader;
  merchantUploader=createUploader({
    inputId:'m-image-file',
    title:'Drop the restaurant photo here',
    hint:'or click to browse · JPEG, PNG or WebP · under 5 MB · automatically resized & optimised',
    // Smaller than a bucket cover: the bytes live in the document and the
    // customer home screen loads every merchant at once, so keep them light.
    maxW:1000,maxH:500,minW:600,minH:300,quality:0.72,
    pathFor:function(){ return 'inline'; }, // sentinel — no bucket path needed
    upload:inlineUpload,
    removeObject:inlineRemove,
    onChange:function(url){ $('m-imageurl').value=url; },
    toast:toast
  });
  $('m-image-drop').appendChild(merchantUploader.el);
  return merchantUploader;
}
/* Common category icons plus free text — the field is a string, not an enum,
   so the picker is a shortcut rather than a constraint. Widened past the
   original single row of fifteen: with four merchant categories to cover, a
   grocer, a pharmacy and a hardware store were all falling back to typing an
   emoji by hand because none of the shortcuts fitted them. */
var EMOJI_CHOICES=[
  // Food
  '🍽️','🍔','🍕','🍗','🍖','🥘','🍜','🐟','🍤','🥗','🌮','🍟','🍞','🥖','🥞',
  // Sweet / drinks
  '🍰','🧁','🍦','🍫','☕','🥤','🧃','🥛','🍺',
  // Grocery, pharmacy, retail, logistics
  '🛒','🏪','💊','🏥','🧴','🛍️','🎁','📦','🚚'
];
function renderEmojiPicker(){
  var host=$('m-emoji-picker'); if(!host) return;
  host.innerHTML=EMOJI_CHOICES.map(function(e){
    return '<button type="button" class="emoji-opt" data-emoji="'+esc(e)+'" '+
      'aria-label="Use '+esc(e)+'">'+esc(e)+'</button>';
  }).join('');
}
/** Collapsed by default; the current icon is already shown in the field. */
function toggleEmojiPicker(force){
  var host=$('m-emoji-picker'), btn=$('m-emoji-toggle');
  if(!host) return;
  var open=force!=null?force:host.hidden;
  host.hidden=!open;
  if(btn){
    btn.setAttribute('aria-expanded',open?'true':'false');
    btn.textContent=open?'Hide icons':'Choose icon';
  }
}
function pickEmoji(e){
  var input=$('m-emoji'); if(!input) return;
  input.value=input.value===e?'':e;   // clicking the current one clears it
  syncEmojiSelection();
}
/* ── Merchant pickup location (P5-06) ─────────────────────────────────
   The `#m-location` box is a convenience: paste a Google Maps link or a
   "lat, lng" string and it fills the two number fields, which are the source
   of truth `saveMerchant` reads. Parsing lives in location-input.js so it can
   be unit-tested; here we only move values between fields and narrate state. */
function applyLocationPaste(){
  var raw=($('m-location')||{}).value||'';
  if(!raw.trim()){ syncLocationHint(); return; }
  var c=parseLatLng(raw);
  if(c){
    $('m-lat').value=String(roundCoord(c.lat));
    $('m-lng').value=String(roundCoord(c.lng));
    $('m-location').value='';   // consumed — the number fields now own it
  }
  syncLocationHint(c?null:'invalid');
}
function syncLocationHint(state){
  var el=$('m-location-hint'); if(!el) return;
  var lat=parseFloat(($('m-lat')||{}).value);
  var lng=parseFloat(($('m-lng')||{}).value);
  if(state==='invalid'){
    // A shortened maps.app.goo.gl link carries no coordinates until a browser
    // follows it, so say what to paste instead of failing silently.
    el.hidden=false;
    el.innerHTML=icon('close')+'Could not read coordinates from that. Paste a full Google Maps link or “lat, lng”.';
    return;
  }
  if(isValidLatLng(lat,lng)){
    el.hidden=false;
    el.innerHTML=icon('check')+'Pickup set to '+esc(formatLatLng(lat,lng))+' — drivers will be dispatched nearest-first.';
    return;
  }
  // No coordinates yet: this merchant's orders fall back to arrival order.
  el.hidden=false;
  el.innerHTML=icon('info')+'No location yet. Orders still work, but drivers won’t be ranked by distance to this merchant.';
}
function syncEmojiSelection(){
  var current=($('m-emoji')||{}).value||'';
  var host=$('m-emoji-picker'); if(!host) return;
  Array.prototype.forEach.call(host.querySelectorAll('.emoji-opt'),function(b){
    var on=b.getAttribute('data-emoji')===current;
    b.classList.toggle('sel',on);
    b.setAttribute('aria-pressed',on?'true':'false');
  });
}
function openMerchantModal(mode,id){
  merchantMode=mode; merchantEditId=id||null;
  var isEdit=mode==='edit';
  $('mer-modal-title').textContent=isEdit?'Edit Merchant':'Add New Merchant';
  $('mer-save-btn').innerHTML=icon('check')+(isEdit?'Update':'Add Merchant');
  // Matches the driver modal: once the record exists there is nothing left to
  // cancel, so the escape hatch says what it actually does.
  $('mer-cancel-btn').textContent=isEdit?'Close':'Cancel';
  var m=isEdit?merchants.find(function(x){ return x.id===id; }):null;
  $('m-name').value    =m?m.name:'';
  $('m-cat').value     =m?m.category:'Food';
  $('m-owner').value   =m?(m.owner||''):'';
  $('m-phone').value   =m?m.phone:'';
  $('m-email').value   =m?(m.email||''):'';
  $('m-fee').value     =m?String(m.deliveryFee):'';
  $('m-hours').value   =m?m.openingHours:'';
  $('m-etatime').value =m?m.deliveryTime:'';
  $('m-address').value =m?m.address:'';
  $('m-status').value  =m?(m.open?'Open':'Closed'):'Open';
  $('m-imageurl').value=m?(m.imageUrl||''):'';
  $('m-emoji').value   =m?(m.emoji||''):'';
  // Pickup coordinates (P5-06). The paste box is only an input aid, so it always
  // starts empty; the lat/lng number fields below are the source of truth.
  $('m-location').value='';
  $('m-lat').value     =(m&&m.lat!=null)?String(m.lat):'';
  $('m-lng').value     =(m&&m.lng!=null)?String(m.lng):'';
  syncLocationHint();
  syncEmojiSelection();
  // Always re-collapsed: an open grid left over from the previous merchant is
  // state from a form the admin has already finished with.
  toggleEmojiPicker(false);

  var up=mountMerchantUploader();
  up.setValue(m?(m.imageUrl||''):'');
  // Inline images need no bucket path, so the zone is usable even while adding a
  // brand-new merchant — the photo is saved together with the form on submit.
  up.setEnabled(true);
  $('m-image-locked').hidden=true;
  openModal('modal-merchant');
}
function saveMerchant(){
  var name=$('m-name').value.trim();
  if(!name){ toast('warning','Business name is required.'); $('m-name').focus(); return; }
  var isOpenState=$('m-status').value==='Open';

  /* P3-01. The delivery fee is written as an INTEGER, not '$'+value.
     The old string write is the root of the three-different-numbers bug:
     the admin configured '$250', the customer regex-scraped a number out of a
     different field, and when that failed it fell back to a hardcoded 100 —
     so a J$250 fee was displayed as J$250 and charged as J$100. */
  var feeRaw=$('m-fee').value.trim();
  var deliveryFee=Math.round(parseAmt(feeRaw));
  if(feeRaw!==''&&!isFinite(deliveryFee)){
    toast('warning','Delivery fee must be a number.'); $('m-fee').focus(); return;
  }
  if(deliveryFee<0){
    toast('warning','Delivery fee cannot be negative.'); $('m-fee').focus(); return;
  }

  /* Pickup coordinates (P5-06). Optional — a merchant with no location still
     takes orders; they just miss nearest-first driver dispatch. But a
     half-entered pair (one field filled, or an out-of-range value) is a typo
     that would denormalise a broken pickup onto every future order, so refuse
     it rather than store it. */
  var latRaw=($('m-lat').value||'').trim(), lngRaw=($('m-lng').value||'').trim();
  var hasLat=latRaw!=='', hasLng=lngRaw!=='';
  var lat=null, lng=null;
  if(hasLat||hasLng){
    if(!hasLat||!hasLng){
      toast('warning','A pickup location needs both latitude and longitude.');
      $((hasLat?'m-lng':'m-lat')).focus(); return;
    }
    lat=roundCoord(Number(latRaw)); lng=roundCoord(Number(lngRaw));
    if(!isValidLatLng(lat,lng)){
      toast('warning','That pickup location is out of range. Latitude −90…90, longitude −180…180.');
      $('m-lat').focus(); return;
    }
  }

  var obj={name:name,category:$('m-cat').value,owner:$('m-owner').value.trim()||'—',
    phone:phoneFmt($('m-phone').value)||'—',email:$('m-email').value.trim()||'—',
    address:$('m-address').value.trim()||'—',
    // Business hours and delivery ETA are separate fields (SCHEMA.md).
    openingHours:$('m-hours').value.trim()||'—',
    deliveryTime:$('m-etatime').value.trim()||'25–35 min',
    deliveryFee:deliveryFee,
    isOpen:isOpenState,
    // P4-02. Customer-facing display icon (home_screen.dart:672). Until now
    // the panel had no input for it, so every admin-created merchant fell
    // back to a generic plate while seeded ones had bespoke icons.
    emoji:$('m-emoji').value.trim()||'',
    // P5-06. Written as numbers (or null when cleared) so the customer app can
    // denormalise them onto orders as pickupLat/pickupLng for nearest-first
    // dispatch. Null is a valid "no location" — never 0, which reads as a place.
    lat:lat,lng:lng,
    imageUrl:$('m-imageurl').value.trim()||'',updatedAt:serverTimestamp()};
  var btn=$('mer-save-btn'), isEdit=merchantMode==='edit';
  btn.disabled=true; btn.innerHTML='<span class="spin"></span>Saving…';
  var promise;
  if(isEdit){ promise=updateDoc(doc(db,'merchants',merchantEditId),obj); }
  else{
    // A new merchant starts with no ratings, not a perfect one. `ordersToday`
    // is no longer stored at all — it is derived (P3-05).
    obj.totalRatings=0; obj.ratingCount=0; obj.averageRating=0;
    obj.createdAt=serverTimestamp();
    promise=addDoc(collection(db,'merchants'),obj);
  }
  promise.then(function(created){
    btn.disabled=false;
    btn.innerHTML=icon('check')+(isEdit?'Update':'Add Merchant');
    if(isEdit){
      closeModal('modal-merchant');
      toast('success','Merchant updated.');
      return;
    }
    /* A new merchant has no id until this write lands, and there is nowhere
       to upload a photo to without one. Rather than leave the admin to find
       the merchant again in the table, stay open and switch to edit mode —
       the upload zone unlocks in place. */
    toast('success','Merchant added — you can add a photo now.');
    openMerchantModal('edit',created.id);
    var live=merchants.find(function(x){ return x.id===created.id; });
    if(!live){
      // The snapshot listener has not delivered the new document yet, so
      // openMerchantModal found nothing to prefill. Put the typed values back.
      $('m-name').value=name; $('m-cat').value=obj.category;
      $('m-owner').value=obj.owner; $('m-phone').value=obj.phone;
      $('m-email').value=obj.email; $('m-fee').value=String(deliveryFee);
      $('m-hours').value=obj.openingHours; $('m-etatime').value=obj.deliveryTime;
      $('m-address').value=obj.address; $('m-status').value=isOpenState?'Open':'Closed';
      $('m-emoji').value=obj.emoji; syncEmojiSelection();
      $('m-lat').value=obj.lat!=null?String(obj.lat):'';
      $('m-lng').value=obj.lng!=null?String(obj.lng):'';
      syncLocationHint();
    }
  }).catch(function(e){
    toast('error',e.message,'Could not save merchant');
    btn.disabled=false; btn.innerHTML=icon('check')+(isEdit?'Update':'Add Merchant');
  });
}
function deleteMerchant(id){
  var m=merchants.find(function(x){ return x.id===id; }); if(!m) return;
  confirmDialog({title:'Delete merchant?',body:'“'+m.name+'” and its menu items will be permanently removed. This cannot be undone.',confirmLabel:'Delete merchant'})
    .then(function(ok){
      if(!ok) return;
      deleteDoc(doc(db,'merchants',id))
        .then(function(){
          toast('success','Merchant deleted.');
          // Images are stored inline in the merchant/menu documents, so deleting
          // the documents takes the photos with them — no bucket to sweep.
        })
        .catch(function(e){ toast('error',e.message,'Delete failed'); });
    });
}
function toggleMerchant(id){
  var m=merchants.find(function(x){ return x.id===id; }); if(!m) return;
  updateDoc(doc(db,'merchants',id),{isOpen:!m.open,updatedAt:serverTimestamp()})
    .catch(function(e){ toast('error',e.message,'Could not change status'); });
}
function openMerchantPanel(id){
  panelMerchantId=id;
  var m=merchants.find(function(x){ return x.id===id; }); if(!m) return;
  $('sp-sub').textContent='Merchant Profile';
  $('sp-title').textContent=m.name;
  var recent=orders.filter(function(o){ return m.id&&o.merchantId===m.id; });
  if(!recent.length) recent=orders.filter(function(o){ return o.merchant===m.name; });
  var recentHtml=recent.slice(0,5).map(function(o){
    return '<div class="sp-row"><span class="sp-lbl">'+esc(o.id)+' — '+esc(o.customer)+'</span>'+
      '<span class="sp-val">'+badge(o.status)+'</span></div>';
  }).join('')||'<div class="empty-copy">No orders recorded yet.</div>';

  var detailsHtml=
    '<div class="sp-hero">'+merchantMedia(m,'lg')+
      '<div><div class="sp-hero-name">'+esc(m.name)+'</div><div style="margin-top:5px">'+badge(m.open?'Open':'Closed')+'</div></div></div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Business Details</div>'+
      row('Category','<span class="bdg bg-info plain">'+esc(m.category)+'</span>')+
      row('Owner',esc(m.owner))+
      row('Opening Hours','<span class="sp-val sm">'+esc(m.openingHours||'—')+'</span>',true)+
      row('Delivery ETA','<span class="sp-val sm">'+esc(m.deliveryTime||'—')+'</span>')+
      row('Delivery Fee','<span class="num">'+esc(m.deliveryFee===0?'Free':money(m.deliveryFee))+'</span>')+
      row('Address','<span class="sp-val sm">'+esc(m.address)+'</span>',true)+
      // P5-06. Whether this merchant feeds nearest-first driver dispatch.
      row('Pickup Location',(m.lat!=null&&m.lng!=null)
        ?'<span class="sp-val sm num">'+esc(formatLatLng(m.lat,m.lng))+'</span>'
        :'<span class="sp-val sm" style="color:var(--gold)">Not set — no distance ranking</span>',true)+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Contact</div>'+
      row('Phone','<span class="num">'+esc(phoneFmt(m.phone))+'</span>')+
      row('Email','<span class="sp-val sm">'+esc(m.email)+'</span>',true)+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Stats</div>'+
      '<div class="sp-row"><span class="sp-lbl">Orders Today</span><span class="sp-val money">'+ordersTodayFor(m.id)+'</span></div>'+
      row('Rating',starsOrNone(m.rating,m.ratingCount))+'</div>'+
    '<div class="sp-sec"><div class="sp-sec-title">Recent Orders</div>'+recentHtml+'</div>';

  $('sp-body').innerHTML=
    '<div class="tabs" style="width:100%">'+
      '<div id="mptab-details" class="tab active" data-mtab="details" style="flex:1;justify-content:center">Details</div>'+
      '<div id="mptab-menu" class="tab" data-mtab="menu" style="flex:1;justify-content:center">Menu Items</div>'+
    '</div>'+
    '<div id="merch-tab-details">'+detailsHtml+'</div>'+
    '<div id="merch-tab-menu" hidden></div>';
  openSidePanel();
}
function switchMerchantTab(tab){
  $('mptab-details').classList.toggle('active',tab==='details');
  $('mptab-menu').classList.toggle('active',tab==='menu');
  $('merch-tab-details').hidden=tab!=='details';
  $('merch-tab-menu').hidden=tab!=='menu';
  if(tab==='menu') loadMenuItemsTab(panelMerchantId);
}
function loadMenuItemsTab(merchantId){
  if(menuItemsUnsub){ menuItemsUnsub(); menuItemsUnsub=null; }
  menuItemEditId=null;
  var el=$('merch-tab-menu'); if(!el) return;
  el.innerHTML=
    '<div class="mi-form">'+
      '<div class="mi-form-title" id="mi-form-title">Add Menu Item</div>'+
      '<div class="fr"><label for="mi-name">Name *</label><input id="mi-name" placeholder="Item name"/></div>'+
      '<div class="fr"><label for="mi-desc">Description</label><input id="mi-desc" placeholder="Brief description"/></div>'+
      '<div class="fr"><label for="mi-price">Price ($) *</label><input id="mi-price" type="number" placeholder="1200" min="0"/></div>'+
      '<div class="fr"><label for="mi-cat">Category</label>'+
        '<select id="mi-cat"><option value="mains">Mains</option><option value="sides">Sides</option>'+
        '<option value="drinks">Drinks</option><option value="popular">Popular</option></select></div>'+
      '<div class="fr"><label>Item Photo <small>(optional)</small></label><div id="mi-image-drop"></div></div>'+
      '<input id="mi-img" type="hidden"/>'+
      '<div style="display:flex;gap:8px;margin-top:12px">'+
        '<button class="btn btn-outline" id="mi-cancel-btn" data-action="cancel-menu-item" style="flex:1;display:none">Cancel</button>'+
        '<button class="btn btn-primary" data-action="save-menu-item" style="flex:1">'+icon('check')+'Save Item</button>'+
      '</div>'+
    '</div>'+
    '<div id="menu-items-list">'+
      '<div class="mi-card"><div class="sk sk-sq" style="width:40px;height:40px"></div>'+
      '<div style="flex:1"><div class="sk sk-line" style="width:58%;margin-bottom:7px"></div>'+
      '<div class="sk sk-line" style="width:34%"></div></div></div>'+
      '<div class="mi-card"><div class="sk sk-sq" style="width:40px;height:40px"></div>'+
      '<div style="flex:1"><div class="sk sk-line" style="width:44%;margin-bottom:7px"></div>'+
      '<div class="sk sk-line" style="width:28%"></div></div></div>'+
    '</div>';

  /* P4-02. Same component as the merchant cover, smaller bounds — these render
     as ~72px thumbnails in merchant_menu_screen.dart, so anything larger is
     bytes for no visible gain, and here those bytes live inline in the item
     document. The panel is rebuilt every time the tab opens, so the uploader is
     rebuilt with it. */
  menuItemUploader=createUploader({
    inputId:'mi-image-file',
    title:'Drop the item photo here',
    hint:'or click to browse · JPEG, PNG or WebP · under 5 MB · automatically resized & optimised',
    maxW:500,maxH:375,minW:300,minH:225,quality:0.72,
    pathFor:function(){ return 'inline'; }, // sentinel — image stored in the doc
    upload:inlineUpload,
    removeObject:inlineRemove,
    onChange:function(url){ var f=$('mi-img'); if(f) f.value=url; },
    toast:toast
  });
  $('mi-image-drop').appendChild(menuItemUploader.el);

  try{
    menuItemsUnsub=onSnapshot(
      collection(db,'merchants',merchantId,'menuItems'),
      function(snap){
        panelMenuItems=snap.docs.map(function(d){
          var o=d.data();
          return {id:d.id,name:o.name||'',description:o.description||'',price:Number(o.price)||0,
            category:o.category||'mains',imageUrl:o.imageUrl||''};
        });
        renderMenuItems();
      },
      function(e){ console.warn('menuItems:',e.message); toast('error',e.message,'Could not load menu'); }
    );
  }catch(e){ console.warn('menuItems init:',e.message); }
}
function renderMenuItems(){
  var listEl=$('menu-items-list'); if(!listEl) return;
  if(!panelMenuItems.length){
    listEl.innerHTML=emptyState('store','No menu items yet','Add the first dish or product using the form above.');
    return;
  }
  listEl.innerHTML=panelMenuItems.map(function(item){
    var media=item.imageUrl
      ? '<img class="thumb" src="'+esc(item.imageUrl)+'" alt="" onerror="this.outerHTML=this.dataset.fb" data-fb="'+esc('<div class="cat-ico c-food">'+icon('cat-food')+'</div>')+'">'
      : '<div class="cat-ico c-food">'+icon('cat-food')+'</div>';
    return '<div class="mi-card">'+media+
      '<div style="flex:1;min-width:0">'+
        '<div class="mi-name">'+esc(item.name)+'</div>'+
        (item.description?'<div class="mi-desc">'+esc(item.description)+'</div>':'')+
        '<div style="display:flex;align-items:center;gap:8px;margin-top:4px">'+
          '<span class="mi-price">'+money(item.price)+'</span>'+
          '<span class="bdg bg-info plain" style="font-size:10px;text-transform:capitalize">'+esc(item.category)+'</span>'+
        '</div>'+
      '</div>'+
      '<div class="cell-actions">'+
        '<button class="aicon ai-e" data-action="edit-menu-item" data-id="'+esc(item.id)+'" title="Edit" aria-label="Edit item">'+icon('edit')+'</button>'+
        '<button class="aicon ai-d" data-action="del-menu-item" data-id="'+esc(item.id)+'" title="Delete" aria-label="Delete item">'+icon('delete')+'</button>'+
      '</div>'+
    '</div>';
  }).join('');
}
function editMenuItemFn(id){
  var item=panelMenuItems.find(function(i){ return i.id===id; }); if(!item) return;
  menuItemEditId=id;
  $('mi-form-title').textContent='Edit Menu Item';
  $('mi-name').value=item.name;
  $('mi-desc').value=item.description;
  $('mi-price').value=item.price;
  $('mi-cat').value=item.category;
  $('mi-img').value=item.imageUrl;
  if(menuItemUploader) menuItemUploader.setValue(item.imageUrl);
  $('mi-cancel-btn').style.display='';
  $('mi-name').scrollIntoView({behavior:reduceMotion()?'auto':'smooth',block:'nearest'});
}
function cancelMenuItemEdit(){
  menuItemEditId=null;
  $('mi-form-title').textContent='Add Menu Item';
  ['mi-name','mi-desc','mi-price','mi-img'].forEach(function(id){ var el=$(id); if(el) el.value=''; });
  var cat=$('mi-cat'); if(cat) cat.value='mains';
  if(menuItemUploader) menuItemUploader.reset();
  var cb=$('mi-cancel-btn'); if(cb) cb.style.display='none';
}
function saveMenuItem(){
  var name=($('mi-name').value||'').trim();
  var price=parseInt($('mi-price').value,10)||0;
  if(!name){ toast('warning','Item name is required.'); $('mi-name').focus(); return; }
  if(!price){ toast('warning','Price is required.'); $('mi-price').focus(); return; }
  var obj={name:name,description:($('mi-desc').value||'').trim(),price:price,
    category:$('mi-cat').value,imageUrl:($('mi-img').value||'').trim()};
  var isEdit=!!menuItemEditId;
  var promise=isEdit
    ? updateDoc(doc(db,'merchants',panelMerchantId,'menuItems',menuItemEditId),obj)
    : addDoc(collection(db,'merchants',panelMerchantId,'menuItems'),obj);
  promise.then(function(){
    cancelMenuItemEdit();
    toast('success',isEdit?'Menu item updated.':'Menu item added.');
  }).catch(function(e){ toast('error',e.message,'Could not save item'); });
}
function deleteMenuItemFn(id){
  var item=panelMenuItems.find(function(i){ return i.id===id; });
  confirmDialog({title:'Delete menu item?',body:item?'“'+item.name+'” will be removed from this merchant’s menu.':'This item will be removed.',confirmLabel:'Delete item'})
    .then(function(ok){
      if(!ok) return;
      deleteDoc(doc(db,'merchants',panelMerchantId,'menuItems',id))
        .then(function(){
          toast('success','Menu item deleted.');
          // Inline image — removed with the document, nothing else to clean up.
        })
        .catch(function(e){ toast('error',e.message,'Delete failed'); });
    });
}

// ══════════════════════ NOTIFICATIONS ══════════════════════
function updPhonePreview(){
  var title=$('n-title').value, msg=$('n-msg').value;
  $('pv-title').textContent=title||'Notification Title';
  $('pv-msg').textContent=msg||'Your message will appear here.';
  // NT-5: live character counters. `maxlength` on the inputs is the hard stop;
  // this shows how close the admin is and turns amber in the last ~15%.
  setCharCount('n-title-count',title.length,65);
  setCharCount('n-msg-count',msg.length,178);
}
function setCharCount(id,len,max){
  var el=$(id); if(!el) return;
  el.textContent=len+' / '+max;
  el.classList.toggle('char-count-warn',len>=max*0.85);
  el.classList.toggle('char-count-full',len>=max);
}
function renderNotifHist(){
  var el=$('notif-hist'); if(!el) return;
  if(!loadedOnce.notifs){
    el.innerHTML='<div class="nh-item"><div class="sk sk-sq" style="width:38px;height:38px"></div>'+
      '<div style="flex:1"><div class="sk sk-line" style="width:52%;margin-bottom:8px"></div>'+
      '<div class="sk sk-line" style="width:76%"></div></div></div>';
    return;
  }
  if(!notifHistory.length){
    el.innerHTML=emptyState('bell','Nothing sent yet','Push notifications you send will appear here with their audience, timestamp, and delivery count.');
    return;
  }
  el.innerHTML=notifHistory.map(function(n){
    // deliveredCount / openedCount / failedCount are written back by
    // onNotificationCreated after the send; each is briefly null on a
    // just-sent push, so each is only shown once present.
    var mute='font-size:11px;color:var(--text-mute)';
    var stat=function(txt){ return '<span style="'+mute+'" class="num">'+txt+'</span>'; };
    var chips=[];
    if(n.delivered!=null) chips.push(stat('Delivered to '+n.delivered+' device'+(n.delivered===1?'':'s')));
    if(n.opened!=null){
      chips.push(stat(n.opened+' opened'));
      if(n.delivered) chips.push(stat('Tap rate '+Math.round((n.opened/n.delivered)*100)+'%'));
    }
    if(n.failed) chips.push('<span style="font-size:11px;color:var(--danger)" class="num">'+n.failed+' failed</span>');
    // NT-3: a scheduled push that has not gone out yet.
    var schedChip='';
    if(n.scheduledFor&&!n.dispatched){
      schedChip='<span class="bdg bg-warning plain sm">⏱ '+esc(n.scheduledFor.toLocaleString('en-JM',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}))+'</span>';
    }
    // NT-4: the tap destination.
    var destChip=n.destType?'<span class="bdg bg-neutral plain sm">→ '+esc(n.destType)+(n.destValue?': '+esc(n.destValue):'')+'</span>':'';
    return '<div class="nh-item"><div class="nh-ico">'+icon('notifications')+'</div>'+
      '<div style="min-width:0">'+
        '<div class="nh-title">'+esc(n.title)+'</div>'+
        '<div class="nh-meta">'+esc(n.msg)+'</div>'+
        '<div style="display:flex;gap:8px;align-items:center;margin-top:7px;flex-wrap:wrap">'+
          '<span class="bdg bg-info plain">'+esc(n.target)+'</span>'+
          schedChip+destChip+
          stat(esc(n.time))+
          (n.sentBy?stat('by '+esc(n.sentBy)):'')+
          chips.join('')+
        '</div>'+
      '</div></div>';
  }).join('');
}
/* Writing this document triggers the onNotificationCreated function, which sends
   a REAL FCM push to every device in the target audience (functions/notifications.ts).
   It is not a log. The confirm below exists because there is no undo on a push. */
var NOTIF_AUDIENCE={
  all:'everyone (customers and drivers)',customers:'all customers',drivers:'all drivers',
  ordered:'customers who have ordered',never_ordered:'customers who never ordered',
  inactive:'inactive customers'
};
function notifAudienceLabel(target){
  if(NOTIF_AUDIENCE[target]) return NOTIF_AUDIENCE[target];
  if(target&&target.indexOf('tag:')===0) return tagLabel(target.slice(4))+' customers';
  return target;
}
/* NT-2: the customer-segment options come from the CU-4 tag catalogue, so the
   two lists cannot drift. */
function fillNotifTagOptions(){
  var g=$('n-target-tags'); if(!g||g.children.length) return;
  g.innerHTML=CUSTOMER_TAGS.map(function(t){
    return '<option value="tag:'+esc(t.slug)+'">'+esc(t.label)+' customers</option>';
  }).join('');
}
/* NT-4: reveal the right value control for the chosen destination. */
function syncNotifDest(){
  var dest=($('n-dest')||{}).value||'';
  var row=$('n-dest-value-row'); if(!row) return;
  row.hidden=!dest||dest==='';
  var isScreen=dest==='screen';
  $('n-dest-value').hidden=isScreen;
  $('n-dest-screen').hidden=!isScreen;
  var lbl=$('n-dest-value-label');
  if(dest==='search'){ lbl.textContent='Search term'; $('n-dest-value').placeholder='grocery'; }
  else if(dest==='url'){ lbl.textContent='Web address'; $('n-dest-value').placeholder='https://…'; }
  else if(isScreen){ lbl.textContent='Screen'; }
}
/* NT-3: the Schedule button appears once a date is picked; Send is disabled
   then, so the two are never ambiguous. */
function syncNotifSchedule(){
  var when=($('n-schedule')||{}).value||'';
  var sched=$('notif-schedule-btn'), send=$('notif-send-btn');
  if(sched) sched.hidden=!when;
  if(send) send.disabled=!!when;
}
function notifDestFields(){
  var dest=($('n-dest')||{}).value||'';
  if(!dest) return {};
  var val=dest==='screen'?($('n-dest-screen')||{}).value:($('n-dest-value')||{}).value;
  val=(val||'').trim();
  if(!val) return {};
  return {destType:dest,destValue:val};
}
function sendNotif(scheduled){
  var title=$('n-title').value.trim();
  var msg=$('n-msg').value.trim();
  var target=$('n-target').value;
  if(!title||!msg){ toast('warning','Enter both a title and a message.'); return; }
  var audience=notifAudienceLabel(target);
  var dest=notifDestFields();

  var whenRaw=($('n-schedule')||{}).value||'';
  var scheduledFor=null;
  if(scheduled){
    if(!whenRaw){ toast('warning','Pick a date and time to schedule for.'); $('n-schedule').focus(); return; }
    var sd=new Date(whenRaw);
    if(isNaN(sd.getTime())||sd.getTime()<=Date.now()){ toast('warning','Choose a time in the future.'); $('n-schedule').focus(); return; }
    scheduledFor=Timestamp.fromDate(sd);
  }

  confirmDialog({
    tone:'warning',
    title:scheduled?'Schedule this push?':'Send this push?',
    body:(scheduled
      ? 'This will send to '+audience+' at '+new Date(whenRaw).toLocaleString('en-JM',{dateStyle:'medium',timeStyle:'short'})+'.'
      : 'This sends a real push notification to '+audience+'. It cannot be recalled once sent.')+
      (dest.destType?' Tapping it opens: '+dest.destType+' → '+dest.destValue+'.':''),
    confirmLabel:scheduled?'Schedule it':'Send Notification'
  }).then(function(ok){
    if(!ok) return;
    var btnId=scheduled?'notif-schedule-btn':'notif-send-btn';
    var btn=$(btnId), orig=btn.innerHTML;
    btn.disabled=true; btn.innerHTML='<span class="spin"></span>'+(scheduled?'Scheduling…':'Sending…');
    var payload={
      title:title,message:msg,target:target,
      sentBy:auth.currentUser?auth.currentUser.email:'admin',
      createdAt:serverTimestamp()
    };
    if(dest.destType){ payload.destType=dest.destType; payload.destValue=dest.destValue; }
    if(scheduledFor) payload.scheduledFor=scheduledFor;
    addDoc(collection(db,'notifications'),payload).then(function(){
      ['n-title','n-msg','n-schedule','n-dest-value'].forEach(function(f){ var el=$(f); if(el) el.value=''; });
      $('n-dest').value=''; syncNotifDest(); syncNotifSchedule();
      updPhonePreview();
      btn.disabled=false; btn.innerHTML=orig;
      toast('success',scheduled?'Scheduled for '+audience+'.':'Push sent to '+audience+'.',scheduled?'Scheduled':'Sent');
    }).catch(function(e){
      toast('error',e.message,scheduled?'Could not schedule':'Could not send notification');
      btn.disabled=false; btn.innerHTML=orig;
    });
  });
}

// ══════════════════════ PROMO CODES ══════════════════════
/* "2026-08-18" -> "August 18, 2026" for the live preview (checklist PR-8).
   Parsed as a local date, not UTC, so the day never slips by a timezone. */
function fmtDateLong(iso){
  if(!iso) return '';
  var p=String(iso).split('-');
  if(p.length!==3) return iso;
  var d=new Date(Number(p[0]),Number(p[1])-1,Number(p[2]));
  if(isNaN(d.getTime())) return iso;
  return d.toLocaleDateString('en-JM',{year:'numeric',month:'long',day:'numeric'});
}
function updPromoPreview(){
  var code=($('pc-code').value||'PROMO').toUpperCase();
  var disc=$('pc-disc').value, type=$('pc-type').value, valid=$('pc-valid').value;
  var maxDisc=$('pc-maxdisc').value;
  $('pcp-code').textContent=code;
  $('pcp-disc').textContent=disc?(type==='percent'?disc+'% OFF':money(disc)+' OFF'):'—';
  // PR-9: surface the max-discount cap the form already captures.
  $('pcp-max').textContent=(disc&&type==='percent'&&maxDisc)?('Up to '+money(maxDisc)):'';
  $('pcp-valid').textContent=valid?('Valid until '+fmtDateLong(valid)):'Never expires';
}
/* Live usage against the cap (P3-03). `usedCount` was never incremented before
   redemption moved server-side, so this column read 0 forever. */
function usageBar(used,max){
  if(!max) return '<span class="num">'+used+'</span>';
  var pct=Math.min(100,Math.round((used/max)*100));
  var tone=pct>=100?"u-danger":(pct>=80?"u-warning":"u-ok");
  return '<span class="num">'+used+'</span>'+
    '<span class="usage-track" role="img" aria-label="'+used+' of '+max+' uses">'+
      '<span class="usage-fill '+tone+'" style="width:'+pct+'%"></span></span>';
}
function renderPromos(){
  var tbody=$('promos-tbody'); if(!tbody) return;
  if(!loadedOnce.promos){ tbody.innerHTML=skeletonRows(7,4); return; }
  if(!promoCodes.length){
    tbody.innerHTML=emptyRow(7,'ticket','No promo codes yet','Create a promo code on the left to make it available at checkout.');
    return;
  }
  tbody.innerHTML=promoCodes.map(function(p){
    // PR-10: Edit · Pause/Resume · Duplicate · End · Usage · Delete. A code that
    // has ended can only be duplicated or deleted — everything else is moot.
    var a=[];
    if(!p.ended){
      a.push(pa('edit-promo',p.id,'Edit'));
      a.push(p.paused?pa('resume-promo',p.id,'Resume'):pa('pause-promo',p.id,'Pause'));
    }
    a.push(pa('dup-promo',p.id,'Duplicate'));
    if(!p.ended) a.push(pa('end-promo',p.id,'End'));
    a.push(pa('usage-promo',p.id,'Usage'));
    a.push(pa('del-promo',p.id,'Delete','pa-del'));
    // PR-5: a small line under the code naming what it's restricted to, if
    // anything — so "why didn't this apply?" has an answer right in the table.
    var eligNote=PromoEligibility.describeEligibility(p.eligibility);
    return '<tr>'+
      '<td><b class="cell-id" style="letter-spacing:1.2px">'+esc(p.code)+'</b>'+
        (eligNote?'<div class="cell-mute" style="font-size:10.5px;font-weight:500;margin-top:2px">'+esc(eligNote)+'</div>':'')+
      '</td>'+
      '<td class="cell-strong">'+esc(p.discount)+'</td>'+
      '<td class="right num">'+usageBar(p.usedCount,p.maxUses)+'</td>'+
      '<td class="right num">'+(p.maxUses||'∞')+'</td>'+
      '<td class="cell-mute num">'+esc(p.expiresAt?p.expiresAt.toLocaleDateString('en-JM',{year:'numeric',month:'short',day:'numeric'}):'Never')+'</td>'+
      '<td>'+badge(p.status)+'</td>'+
      '<td><div class="promo-acts">'+a.join('')+'</div></td>'+
    '</tr>';
  }).join('');
}
/* One small text button in the promo actions cell. */
function pa(action,id,label,cls){
  return '<button class="pa-btn'+(cls?' '+cls:'')+'" data-action="'+action+'" data-id="'+esc(id)+'">'+esc(label)+'</button>';
}
// ── PR-5: eligibility form helpers ──────────────────────────────────────
/* The merchant/customer pickers are rebuilt from whatever `merchants` /
   `customers` already hold in memory — both are live-synced elsewhere, so
   this just needs calling again whenever either list changes or the promo
   page is opened. Selections already made survive a rebuild by id. */
function populateEligPickers(){
  var mSel=$('pc-elig-merchants'), cSel=$('pc-elig-customers');
  if(mSel){
    var mPrev=selVals(mSel);
    var cats={};
    merchants.forEach(function(m){ if(m.category) cats[m.category]=true; });
    mSel.innerHTML=merchants.slice().sort(function(a,b){ return a.name.localeCompare(b.name); })
      .map(function(m){ return '<option value="'+esc(m.id)+'"'+(mPrev.indexOf(m.id)>-1?' selected':'')+'>'+esc(m.name)+'</option>'; }).join('');
    var catSel=$('pc-elig-categories');
    if(catSel){
      var catPrev=selVals(catSel);
      catSel.innerHTML=Object.keys(cats).sort().map(function(c){
        return '<option value="'+esc(c)+'"'+(catPrev.indexOf(c)>-1?' selected':'')+'>'+esc(c)+'</option>';
      }).join('');
    }
  }
  if(cSel){
    var cPrev=selVals(cSel);
    cSel.innerHTML=customers.slice().sort(function(a,b){ return (a.name||'').localeCompare(b.name||''); })
      .map(function(c){
        var label=c.name+(c.phone&&c.phone!=='—'?' · '+c.phone:'');
        return '<option value="'+esc(c.id)+'"'+(cPrev.indexOf(c.id)>-1?' selected':'')+'>'+esc(label)+'</option>';
      }).join('');
  }
}
function selVals(sel){ return Array.prototype.slice.call(sel.selectedOptions||[]).map(function(o){ return o.value; }); }
/* Toggles the "Selected customers" picker's visibility to match the scope
   dropdown — kept hidden (and its selections irrelevant) for every other
   scope, same rule PromoEligibility.buildEligibility applies when reading it. */
function syncEligScope(){
  var wrap=$('pc-elig-customers-wrap');
  if(wrap) wrap.hidden=$('pc-elig-scope').value!=='selected';
}
function readEligForm(){
  return {
    customerScope:$('pc-elig-scope').value||'',
    customerIds:selVals($('pc-elig-customers')),
    merchantIds:selVals($('pc-elig-merchants')),
    categories:selVals($('pc-elig-categories')),
    deliveryAreas:PromoEligibility.parseAreas($('pc-elig-areas').value),
    firstOrderOnly:$('pc-elig-first').checked,
    discountBase:$('pc-elig-base').value||'subtotal',
    orderKinds:['food','package','shop_deliver'].filter(function(k){
      return $('pc-elig-kind-'+(k==='shop_deliver'?'shop':k)).checked;
    })
  };
}
function fillEligForm(elig){
  elig=elig||{};
  $('pc-elig-scope').value=elig.customerScope||'';
  $('pc-elig-base').value=elig.discountBase==='deliveryFee'?'deliveryFee':'subtotal';
  $('pc-elig-areas').value=(elig.deliveryAreas||[]).join(', ');
  $('pc-elig-first').checked=!!elig.firstOrderOnly;
  var kinds=elig.orderKinds&&elig.orderKinds.length?elig.orderKinds:['food','package','shop_deliver'];
  $('pc-elig-kind-food').checked=kinds.indexOf('food')>-1;
  $('pc-elig-kind-package').checked=kinds.indexOf('package')>-1;
  $('pc-elig-kind-shop').checked=kinds.indexOf('shop_deliver')>-1;
  populateEligPickers();
  selectOptionsById($('pc-elig-merchants'),elig.merchantIds||[]);
  selectOptionsById($('pc-elig-categories'),elig.categories||[]);
  selectOptionsById($('pc-elig-customers'),elig.customerIds||[]);
  syncEligScope();
}
function selectOptionsById(sel,ids){
  if(!sel) return;
  Array.prototype.forEach.call(sel.options,function(o){ o.selected=ids.indexOf(o.value)>-1; });
}
function resetEligForm(){ fillEligForm(null); }

function createPromo(){
  var code=$('pc-code').value.trim().toUpperCase();
  var discAmt=parseFloat($('pc-disc').value.trim())||0;
  var discType=$('pc-type').value;
  if(!code){ toast('warning','A promo code is required.'); $('pc-code').focus(); return; }
  if(!discAmt){ toast('warning','A discount amount is required.'); $('pc-disc').focus(); return; }
  var maxUses=parseInt($('pc-max').value,10)||100;
  var minOrderTotal=Math.max(0,Math.round(parseAmt($('pc-min').value)))||0;
  var maxDiscRaw=$('pc-maxdisc').value.trim();
  var maxDiscount=maxDiscRaw===''?null:Math.max(0,Math.round(parseAmt(maxDiscRaw)));

  /* A percentage code with no cap is an unbounded liability — one extra zero
     and a 10%-off code becomes 100% off with nothing to stop it. Refuse rather
     than warn: an uncapped percentage code is not a thing anyone means to
     create. Fixed-amount codes are self-limiting and need no cap. */
  if(discType==='percent'&&maxDiscount==null){
    toast('warning','A percentage code needs a maximum discount. Leaving it uncapped is an unbounded liability.');
    $('pc-maxdisc').focus(); return;
  }
  if(discType==='percent'&&discAmt>100){
    toast('warning','A percentage discount cannot exceed 100%.');
    $('pc-disc').focus(); return;
  }

  // §b — a Timestamp, never a string. The old string write is why expiry was
  // never enforced: the customer read `expiresAt` as a Timestamp and got null.
  var validUntil=$('pc-valid').value||'';
  var expiresAt=null;
  if(validUntil){
    // End of the chosen day, so a code valid "until the 5th" works ON the 5th.
    var d=new Date(validUntil+'T23:59:59');
    if(!isNaN(d.getTime())) expiresAt=Timestamp.fromDate(d);
  }

  // PR-6: an optional scheduled start. `datetime-local` gives a local
  // "YYYY-MM-DDTHH:mm" string; `new Date` reads it in the admin's own zone.
  var startRaw=$('pc-start').value||'';
  var startsAt=null;
  if(startRaw){
    var sd=new Date(startRaw);
    if(!isNaN(sd.getTime())) startsAt=Timestamp.fromDate(sd);
  }
  if(startsAt&&expiresAt&&startsAt.toMillis()>=expiresAt.toMillis()){
    toast('warning','The start date must be before the end date.');
    $('pc-start').focus(); return;
  }

  var editing=!!promoEditId;
  // PR-10: editing overwrites the same document (its id is the code). Usage and
  // the original creation time are carried over from the loaded row, not reset.
  var existing=editing?promoCodes.find(function(x){ return x.id===promoEditId; }):null;
  var fields={
    code:code,discountType:discType,discountAmount:Math.round(discAmt),
    minOrderTotal:minOrderTotal,maxDiscount:maxDiscount,
    maxUses:maxUses,startsAt:startsAt,expiresAt:expiresAt,active:true
  };
  fields.usedCount=editing&&existing?existing.usedCount:0;
  fields.createdAt=serverTimestamp();
  // PR-5. Written as `null`, not omitted, so editing an already-restricted
  // code back down to "everyone" actually clears the old rules rather than
  // leaving them stranded under merge:true.
  fields.eligibility=PromoEligibility.buildEligibility(readEligForm());

  var btn=$('promo-create-btn');
  var restore=editing?icon('edit')+'Save changes':icon('plus')+'Create Promo Code';
  btn.disabled=true; btn.innerHTML='<span class="spin"></span>'+(editing?'Saving…':'Creating…');
  setDoc(doc(db,'promoCodes',code),fields,editing?{merge:true}:undefined).then(function(){
    btn.disabled=false; btn.innerHTML=restore;
    if(editing){ cancelPromoEdit(); toast('success','“'+code+'” updated.'); }
    else{
      ['pc-code','pc-disc','pc-max','pc-start','pc-valid','pc-min','pc-maxdisc'].forEach(function(i){ $(i).value=''; });
      $('pc-type').value='percent';
      resetEligForm();
      updPromoPreview();
      toast('success','Promo code '+code+' is live.');
    }
  }).catch(function(e){
    toast('error',e.message,editing?'Could not save changes':'Could not create promo code');
    btn.disabled=false; btn.innerHTML=restore;
  });
}
function deletePromo(id){
  confirmDialog({title:'Delete promo code?',body:'“'+id+'” will stop working at checkout immediately.',confirmLabel:'Delete code'})
    .then(function(ok){
      if(!ok) return;
      deleteDoc(doc(db,'promoCodes',id))
        .then(function(){ toast('success','Promo code deleted.'); })
        .catch(function(e){ toast('error',e.message,'Delete failed'); });
    });
}

// ── PR-10: promo actions ────────────────────────────────────────────────
/* Pause / Resume just flip `active`. The customer-side check reads it, so a
   paused code stops applying at checkout within a snapshot. */
function pausePromo(id){
  updateDoc(doc(db,'promoCodes',id),{active:false})
    .then(function(){ toast('success','“'+id+'” paused. Resume it any time.'); })
    .catch(function(e){ toast('error',e.message,'Could not pause'); });
}
function resumePromo(id){
  updateDoc(doc(db,'promoCodes',id),{active:true})
    .then(function(){ toast('success','“'+id+'” is live again.'); })
    .catch(function(e){ toast('error',e.message,'Could not resume'); });
}
/* End is terminal: a paused code can come back, an ended one cannot (the UI
   only offers Duplicate / Delete afterwards). `endedAt` is the marker. */
function endPromo(id){
  confirmDialog({title:'End “'+id+'”?',
    body:'It stops working at checkout and cannot be resumed. Duplicate it first if you want to run it again later.',
    confirmLabel:'End promo'})
    .then(function(ok){
      if(!ok) return;
      updateDoc(doc(db,'promoCodes',id),{active:false,endedAt:serverTimestamp()})
        .then(function(){ toast('success','“'+id+'” ended.'); })
        .catch(function(e){ toast('error',e.message,'Could not end promo'); });
    });
}
/* Duplicate clones every rule onto a new code, with usage reset to zero. */
function duplicatePromo(id){
  var p=promoCodes.find(function(x){ return x.id===id; }); if(!p) return;
  $('cf-ico').className='m-ico'; $('cf-ico').innerHTML=icon('plus','ic-lg');
  $('cf-title').textContent='Duplicate “'+p.code+'”';
  $('cf-body').innerHTML='Every rule is copied. Give the new code a name.'+
    '<input id="cf-dupcode" type="text" maxlength="40" placeholder="e.g. '+esc(p.code)+'2" '+
    'style="width:100%;margin-top:10px;text-transform:uppercase"/>';
  var ok=$('cf-ok'); ok.textContent='Create copy'; ok.className='btn btn-primary';
  confirmResolve=function(confirmed){
    var code=(($('cf-dupcode')||{}).value||'').trim().toUpperCase();
    $('cf-body').innerHTML='';
    if(!confirmed) return;
    if(!code){ toast('warning','Give the new code a name.'); return; }
    if(promoCodes.some(function(x){ return x.id===code; })){ toast('warning','“'+code+'” already exists.'); return; }
    setDoc(doc(db,'promoCodes',code),{
      code:code,discountType:p.discountType,discountAmount:Math.round(p.discountAmount||0),
      minOrderTotal:p.minOrderTotal||0,maxDiscount:p.maxDiscount,
      maxUses:p.maxUses||100,usedCount:0,
      startsAt:p.startsAt?Timestamp.fromDate(p.startsAt):null,
      expiresAt:p.expiresAt?Timestamp.fromDate(p.expiresAt):null,
      // PR-5: eligibility rules are part of "every rule" the duplicate copies.
      eligibility:p.eligibility||null,
      active:true,createdAt:serverTimestamp()
    }).then(function(){ toast('success','“'+code+'” created from “'+p.code+'”.'); })
      .catch(function(e){ toast('error',e.message,'Could not duplicate'); });
  };
  openModal('modal-confirm');
}
/* View Usage: a read-only summary. PR-11 (revenue, AOV, …) is a separate,
   bigger piece; this is the redemption count the admin can act on today. */
function viewPromoUsage(id){
  var p=promoCodes.find(function(x){ return x.id===id; }); if(!p) return;
  var cap=p.maxUses?(' of '+p.maxUses):' (no cap)';
  var pct=p.maxUses?' · '+Math.round((p.usedCount/p.maxUses)*100)+'% used':'';
  var last=p.lastRedeemedAt?p.lastRedeemedAt.toLocaleString('en-JM',{dateStyle:'medium',timeStyle:'short'}):'never redeemed';
  toast('info',
    p.usedCount+' redemption'+(p.usedCount===1?'':'s')+cap+pct+'. Last redeemed: '+last+'.',
    '“'+p.code+'” usage');
}
/* Edit prefills the create form. The doc id IS the code, so saving overwrites
   the same document; usedCount and createdAt are preserved (see createPromo). */
function editPromo(id){
  var p=promoCodes.find(function(x){ return x.id===id; }); if(!p) return;
  promoEditId=id;
  $('pc-code').value=p.code; $('pc-code').disabled=true;
  $('pc-type').value=p.discountType||'percent';
  $('pc-disc').value=p.discountAmount!=null?p.discountAmount:'';
  $('pc-max').value=p.maxUses||'';
  $('pc-min').value=p.minOrderTotal||'';
  $('pc-maxdisc').value=p.maxDiscount!=null?p.maxDiscount:'';
  $('pc-valid').value=p.expiresAt?isoDate(p.expiresAt):'';
  $('pc-start').value=p.startsAt?isoLocal(p.startsAt):'';
  fillEligForm(p.eligibility);
  var btn=$('promo-create-btn'); btn.innerHTML=icon('edit')+'Save changes';
  var cancel=$('promo-cancel-btn'); if(cancel) cancel.hidden=false;
  updPromoPreview();
  $('pc-code').scrollIntoView({behavior:reduceMotion()?'auto':'smooth',block:'nearest'});
}
function cancelPromoEdit(){
  promoEditId=null;
  ['pc-code','pc-disc','pc-max','pc-start','pc-valid','pc-min','pc-maxdisc'].forEach(function(i){ var el=$(i); if(el) el.value=''; });
  $('pc-code').disabled=false;
  $('pc-type').value='percent';
  resetEligForm();
  var btn=$('promo-create-btn'); btn.innerHTML=icon('plus')+'Create Promo Code';
  var cancel=$('promo-cancel-btn'); if(cancel) cancel.hidden=true;
  updPromoPreview();
}
function isoDate(dt){ var d=new Date(dt); return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); }
function isoLocal(dt){ return isoDate(dt)+'T'+String(new Date(dt).getHours()).padStart(2,'0')+':'+String(new Date(dt).getMinutes()).padStart(2,'0'); }

// ══════════════════════ ANALYTICS ══════════════════════
function periodStart(p){
  var now=new Date();
  if(p==='Today') return new Date(now.getFullYear(),now.getMonth(),now.getDate());
  if(p==='This Week'){ var d=new Date(now.getFullYear(),now.getMonth(),now.getDate()); d.setDate(d.getDate()-d.getDay()); return d; }
  return new Date(now.getFullYear(),now.getMonth(),1);
}
function renderAnalytics(){
  ['Today','This Week','This Month'].forEach(function(p){
    var start=periodStart(p);
    var os=orders.filter(function(o){ return o._ts&&o._ts>=start; });
    var completed=os.filter(function(o){ return isDeliveredStatus(o.status); });
    var revenue=completed.reduce(function(s,o){ return s+(o.rawTotal!=null?o.rawTotal:parseAmt(o.amount)); },0);
    var uniq=new Set(os.map(function(o){ return o.customer; })).size;
    var avg=completed.length?Math.round(revenue/completed.length):0;
    analyticsStats[p]=[
      {lbl:'Revenue',val:money(revenue),ic:'revenue',accent:'gold'},
      {lbl:'Orders',val:String(os.length),ic:'orders',accent:''},
      {lbl:'Customers',val:String(uniq),ic:'users',accent:'ocean'},
      {lbl:'Avg Order Value',val:money(avg),ic:'receipt',accent:'success'}
    ];
  });
  renderAnalyticsStats();
  renderBarChart();
  renderZones();
  renderPaySplit();
}
function renderAnalyticsStats(){
  var el=$('analytics-stats'); if(!el) return;
  var s=analyticsStats[currentPeriod]||analyticsStats['Today'];
  el.innerHTML=s.map(function(c){
    return '<div class="sc'+(c.accent?' ac-'+c.accent:'')+'"><div class="sc-top"><div>'+
      '<div class="sc-lbl">'+esc(c.lbl)+'</div>'+
      '<div class="sc-val sm num">'+esc(c.val)+'</div></div>'+
      '<div class="sc-chip'+(c.accent?' c-'+c.accent:'')+'">'+icon(c.ic||'analytics')+'</div></div>'+
      '<div class="sc-sub">'+esc(currentPeriod)+'</div></div>';
  }).join('');
}
function barChartData(){
  var now=new Date();
  if(currentPeriod==='Today'){
    return {title:'Hourly Orders — Today',data:[8,10,12,14,16,18,20].map(function(h){
      var s=new Date(now.getFullYear(),now.getMonth(),now.getDate(),h);
      var e=new Date(s.getTime()+7200000);
      return {l:h>12?(h-12)+'PM':(h===12?'12PM':h+'AM'),
        v:orders.filter(function(o){ return o._ts&&o._ts>=s&&o._ts<e; }).length};
    })};
  }
  if(currentPeriod==='This Week'){
    var wk=periodStart('This Week');
    return {title:'Daily Orders — This Week',data:['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map(function(d,i){
      var s=new Date(wk); s.setDate(s.getDate()+i);
      var e=new Date(s); e.setDate(e.getDate()+1);
      return {l:d,v:orders.filter(function(o){ return o._ts&&o._ts>=s&&o._ts<e; }).length};
    })};
  }
  var mStart=periodStart('This Month');
  return {title:'Weekly Orders — This Month',data:['Wk 1','Wk 2','Wk 3','Wk 4'].map(function(w,i){
    var s=new Date(mStart); s.setDate(s.getDate()+i*7);
    var e=new Date(s); e.setDate(e.getDate()+7);
    return {l:w,v:orders.filter(function(o){ return o._ts&&o._ts>=s&&o._ts<e; }).length};
  })};
}
/** Rounded gradient bars, faint gridlines, emphasised max, hover tooltip. */
function renderBarChart(){
  var host=$('bar-chart'); if(!host) return;
  var cfg=barChartData();
  var titleEl=$('bar-title'); if(titleEl) titleEl.textContent=cfg.title;
  var data=cfg.data;
  var W=Math.max(280,host.clientWidth||520), H=190;
  var padL=8,padR=8,padT=24,padB=30;
  var plotH=H-padT-padB, plotW=W-padL-padR;
  var max=Math.max.apply(null,data.map(function(d){ return d.v; }))||1;
  var slot=plotW/data.length, bw=Math.min(46,slot*0.56);

  var grid='';
  for(var g=0;g<=3;g++){
    var y=padT+(plotH/3)*g;
    grid+='<line class="grid-line" x1="'+padL+'" y1="'+y.toFixed(1)+'" x2="'+(W-padR)+'" y2="'+y.toFixed(1)+'"/>';
  }
  var bars=data.map(function(d,i){
    var h=Math.max(3,(d.v/max)*plotH);
    var x=padL+slot*i+(slot-bw)/2;
    var y=padT+plotH-h;
    var cx=padL+slot*i+slot/2;
    // A zero bar reads as a muted baseline stub, never a tiny brand-red sliver.
    var cls=d.v===0?' zero':(d.v===max&&max>0?' max':'');
    return '<g class="bar-g" data-label="'+esc(d.l)+'" data-value="'+d.v+'" data-x="'+cx.toFixed(1)+'" data-y="'+y.toFixed(1)+'">'+
      '<rect class="bar'+cls+'" x="'+x.toFixed(1)+'" y="'+y.toFixed(1)+'" width="'+bw.toFixed(1)+'" height="'+h.toFixed(1)+'" rx="5"/>'+
      '<text class="bar-val" x="'+cx.toFixed(1)+'" y="'+(y-7).toFixed(1)+'">'+d.v+'</text>'+
      '<text class="bar-lbl" x="'+cx.toFixed(1)+'" y="'+(H-10)+'">'+esc(d.l)+'</text>'+
      '<rect class="bar-hit" x="'+(padL+slot*i).toFixed(1)+'" y="'+padT+'" width="'+slot.toFixed(1)+'" height="'+plotH+'"/>'+
    '</g>';
  }).join('');

  host.innerHTML=
    '<svg viewBox="0 0 '+W+' '+H+'" role="img" aria-label="'+esc(cfg.title)+'">'+
      '<defs>'+
        '<linearGradient id="barGrad" x1="0" y1="1" x2="0" y2="0">'+
          '<stop offset="0%" stop-color="#C8102E"/><stop offset="100%" stop-color="#E1495F"/></linearGradient>'+
        '<linearGradient id="barGradMax" x1="0" y1="1" x2="0" y2="0">'+
          '<stop offset="0%" stop-color="#E11D34"/><stop offset="100%" stop-color="#FF6A3D"/></linearGradient>'+
      '</defs>'+grid+bars+
    '</svg><div class="chart-tip" id="chart-tip"></div>';
}
function renderZones(){
  var el=$('zone-chart'); if(!el) return;
  var start=periodStart(currentPeriod);
  var scoped=orders.filter(function(o){ return o._ts&&o._ts>=start; });
  var zones={};
  scoped.forEach(function(o){
    var addr=o.address||'', zone='Other';
    if(/kingston/i.test(addr)) zone='Kingston';
    else if(/portmore/i.test(addr)) zone='Portmore';
    else if(/st\.?\s*thomas|morant/i.test(addr)) zone='St Thomas';
    else if(/st\.?\s*catherine|spanish town/i.test(addr)) zone='St Catherine';
    zones[zone]=(zones[zone]||0)+1;
  });
  var keys=Object.keys(zones);
  if(!keys.length){
    el.innerHTML=emptyState('search','No delivery data','Zones are derived from delivery addresses — none recorded for this period yet.');
    return;
  }
  var total=keys.reduce(function(a,k){ return a+zones[k]; },0)||1;
  el.innerHTML=keys.sort(function(a,b){ return zones[b]-zones[a]; }).slice(0,5).map(function(z){
    var pct=Math.round((zones[z]/total)*100);
    return '<div class="zr"><div class="zn">'+esc(z)+'</div>'+
      '<div class="zt"><div class="zf" data-w="'+pct+'"></div></div>'+
      '<div class="zv">'+zones[z]+'</div></div>';
  }).join('');
  animateBars();
}
function renderTopMerch(){
  var el=$('top-merch'); if(!el) return;
  var counts={},revenue={};
  orders.forEach(function(o){
    var n=o.merchant||'Unknown';
    counts[n]=(counts[n]||0)+1;
    revenue[n]=(revenue[n]||0)+(o.rawTotal!=null?o.rawTotal:parseAmt(o.amount));
  });
  var data=Object.keys(counts).map(function(n){ return {n:n,o:counts[n],r:revenue[n]}; });
  data.sort(function(a,b){ return b.o-a.o; });
  if(!data.length){
    el.innerHTML=emptyRow(3,'store','No merchant activity','Rankings appear once orders start coming in.');
    return;
  }
  el.innerHTML=data.slice(0,5).map(function(m){
    return '<tr><td><b>'+esc(m.n)+'</b></td>'+
      '<td class="right cell-id">'+m.o+'</td>'+
      '<td class="right cell-strong">'+money(m.r)+'</td></tr>';
  }).join('');
}
function renderPaySplit(){
  var el=$('pay-split'); if(!el) return;
  var start=periodStart(currentPeriod);
  var src=orders.filter(function(o){ return o._ts&&o._ts>=start; });
  function has(o,words){
    var p=(o.payment||'').toLowerCase();
    return words.some(function(w){ return p.includes(w); });
  }
  var online=src.filter(function(o){ return has(o,['paypal','card','online']); }).length;
  var cod=src.filter(function(o){ return has(o,['cod','cash']); }).length;
  var total=online+cod;
  if(!total){
    el.innerHTML=emptyState('ticket','No payment data','The payment breakdown appears once orders are recorded for this period.');
    return;
  }
  var onPct=Math.round((online/total)*100), codPct=100-onPct;
  el.innerHTML=
    '<div class="prow"><div class="prow-lbl">Card / PayPal</div>'+
      '<div class="ptrack"><div class="pfill brand" data-w="'+onPct+'"></div></div>'+
      '<div class="prow-pct">'+onPct+'%</div></div>'+
    '<div class="prow"><div class="prow-lbl">Cash on Delivery</div>'+
      '<div class="ptrack"><div class="pfill gold" data-w="'+codPct+'"></div></div>'+
      '<div class="prow-pct">'+codPct+'%</div></div>'+
    '<div class="sc-sub" style="text-align:center;margin-top:10px">Based on '+total+
      ' transaction'+(total===1?'':'s')+' — '+currentPeriod.toLowerCase()+'</div>';
  animateBars();
}
function setPeriod(period){
  currentPeriod=period;
  document.querySelectorAll('.pb').forEach(function(b){ b.classList.toggle('active',b.getAttribute('data-period')===period); });
  renderAnalyticsStats(); renderBarChart(); renderZones(); renderPaySplit();
}

// ══════════════════════ MODAL / SIDE PANEL ══════════════════════
var lastFocus=null;
function openModal(id){ lastFocus=document.activeElement; $(id).classList.add('open'); }
function closeModal(id){ $(id).classList.remove('open'); if(lastFocus&&lastFocus.focus) lastFocus.focus(); }
function openSidePanel(){ $('sp-overlay').classList.add('open'); $('spanel').classList.add('open'); }
function closeSidePanel(){
  $('sp-overlay').classList.remove('open');
  $('spanel').classList.remove('open');
  if(menuItemsUnsub){ menuItemsUnsub(); menuItemsUnsub=null; }
  panelMerchantId=null; panelMenuItems=[]; menuItemUploader=null;
  // Cleared so a late address fetch cannot paint into a panel that has since
  // been closed or reopened on somebody else (P5-05).
  panelCustomerId=null;
  panelInquiryId=null;
}

// ══════════════════════ EVENT DELEGATION ══════════════════════
document.addEventListener('click',function(e){
  var t=e.target;
  /* First, because the chevron sits inside a row's first cell and must not fall
     through to whatever that cell or row is otherwise wired to. */
  var mcx=t.closest('[data-mc-exp]'); if(mcx){ toggleRowExpanded(mcx); return; }
  var ni=t.closest('.ni[data-page]'); if(ni){ navTo(ni.getAttribute('data-page')); return; }
  if(t.closest('#logout-btn')){ doLogout(); return; }
  if(t.closest('#hamburger')){ toggleSidebar(); return; }
  if(t.closest('#theme-btn')){ toggleTheme(); return; }
  var bellPage=t.closest('[data-bell-page]');
  if(bellPage){ toggleBell(false); navTo(bellPage.getAttribute('data-bell-page')); return; }
  if(t.closest('#bell-clear')){ acknowledgeAll(); return; }
  if(t.closest('#bell-btn')){ toggleBell(); return; }
  // A click anywhere outside the open bell menu dismisses it.
  if($('bell-menu')&&$('bell-menu').classList.contains('open')&&!t.closest('.bell-wrap')){ toggleBell(false); }
  if(t.closest('#l-eye')){ togglePassReveal(); return; }
  if(t.closest('#login-btn')){ doLogin(); return; }
  if(t.id==='sp-overlay'||t.closest('#sp-close')){ closeSidePanel(); return; }
  if(t.id==='mob-overlay'){ closeMobileSidebar(); return; }
  if(t.closest('#cf-ok')){ settleConfirm(true); return; }
  if(t.closest('#cf-cancel')){ settleConfirm(false); return; }

  var cb=t.closest('[data-close]'); if(cb){ closeModal(cb.getAttribute('data-close')); return; }
  var mbg=t.closest('.mbg');
  if(mbg&&t===mbg){ if(mbg.id==='modal-confirm') settleConfirm(false); else closeModal(mbg.id); return; }

  var eo=t.closest('.emoji-opt'); if(eo){ pickEmoji(eo.getAttribute('data-emoji')); return; }

  if(t.closest('#add-driver-btn')){ openDriverModal('add'); return; }
  if(t.closest('#add-merchant-btn')){ openMerchantModal('add'); return; }
  if(t.closest('#of-clear')){ clearOrderFilters(); return; }
  // DB-7 dashboard quick actions.
  if(t.closest('[data-action="qa-add-merchant"]')){ openMerchantModal('add'); return; }
  if(t.closest('[data-action="qa-assign-driver"]')){ navTo('orders'); toast('info','Open an order to assign a driver.'); return; }
  if(t.closest('[data-action="qa-send-notif"]')){ navTo('notifications'); return; }

  var pb=t.closest('.pb'); if(pb){ setPeriod(pb.getAttribute('data-period')); return; }
  var mtab=t.closest('[data-mtab]'); if(mtab){ switchMerchantTab(mtab.getAttribute('data-mtab')); return; }
  var tab=t.closest('.tab[data-filter]'); if(tab){ ordersFilter=tab.getAttribute('data-filter'); renderOrders(); return; }
  var otab=t.closest('.tab[data-otab]'); if(otab){ overseasFilter=otab.getAttribute('data-otab'); renderOverseas(); return; }

  var btn=t.closest('[data-action]'); if(!btn) return;
  var action=btn.getAttribute('data-action'),
      id=btn.getAttribute('data-id'),
      oid=btn.getAttribute('data-oid'),
      cid=btn.getAttribute('data-cid'),
      iid=btn.getAttribute('data-iid');
  switch(action){
    case 'view-order':      openOrderPanel(oid); break;
    case 'view-customer':   openCustomerPanel(cid); break;
    case 'toggle-customer': toggleCustomerDisabled(cid); break;
    case 'customer-tags':   editCustomerTags(cid); break;
    case 'customer-orders': viewCustomerOrders(cid); break;
    case 'customer-notify': notifyCustomer(cid); break;
    case 'view-inquiry':    openInquiryPanel(iid); break;
    case 'save-inquiry':    saveInquiry(iid); break;
    case 'save-quote':      saveQuote(iid); break;
    case 'inq-quote':       quoteInquiry(iid); break;
    case 'save-order':      saveOrderChanges(oid); break;
    case 'view-driver':     openDriverPanel(id); break;
    case 'edit-driver':     openDriverModal('edit',id); break;
    case 'del-driver':      deleteDriver(id); break;
    case 'approve-driver':  approveDriver(id); break;
    case 'reject-driver':   rejectDriver(id); break;
    case 'driver-pause':    pauseDriver(id); break;
    case 'driver-suspend':  suspendDriver(id); break;
    case 'driver-resume':   resumeDriver(id); break;
    case 'driver-reinstate':reinstateDriver(id); break;
    case 'driver-assign':   assignFromDriver(id); break;
    case 'driver-active-delivery': driverActiveDelivery(id); break;
    case 'driver-review':   reviewDriverDocs(id); break;
    case 'view-merchant':   openMerchantPanel(id); break;
    case 'edit-merchant':   openMerchantModal('edit',id); break;
    case 'del-merchant':    deleteMerchant(id); break;
    case 'del-promo':       deletePromo(id); break;
    case 'edit-promo':      editPromo(id); break;
    case 'pause-promo':     pausePromo(id); break;
    case 'resume-promo':    resumePromo(id); break;
    case 'dup-promo':       duplicatePromo(id); break;
    case 'end-promo':       endPromo(id); break;
    case 'usage-promo':     viewPromoUsage(id); break;
    case 'cancel-promo-edit': cancelPromoEdit(); break;
    case 'edit-menu-item':  editMenuItemFn(id); break;
    case 'del-menu-item':   deleteMenuItemFn(id); break;
    case 'save-menu-item':  saveMenuItem(); break;
    case 'cancel-menu-item':cancelMenuItemEdit(); break;
    case 'save-driver':     saveDriver(); break;
    case 'gen-driver-pass': fillGeneratedPassword(); break;
    case 'toggle-emoji':    toggleEmojiPicker(); break;
    case 'reset-driver-pass': resetDriverPassword(); break;
    case 'save-merchant':   saveMerchant(); break;
    case 'save-pricing':    savePricing(); break;
    case 'erase-open':      openWipeFlow(); break;
    case 'erase-all':       eraseAllData(); break;
    case 'send-notif':      sendNotif(false); break;
    case 'schedule-notif':  sendNotif(true); break;
    case 'create-promo':    createPromo(); break;
  }
});
document.addEventListener('change',function(e){
  if(e.target.classList.contains('tgl-driver-online')) toggleDriverOnline(e.target.getAttribute('data-id'));
  if(e.target.classList.contains('tgl-merchant')) toggleMerchant(e.target.getAttribute('data-id'));
  // OR-3 / OR-4 order filter + sort dropdowns.
  if(e.target.id&&e.target.id.indexOf('of-')===0) readOrderFilters();
  // DV: driver roster filter.
  if(e.target.id==='drv-filter'){ driverFilter=e.target.value; renderDrivers(); }
  if(e.target.id==='pc-type'||e.target.id==='pc-valid') updPromoPreview();
  if(e.target.id==='pc-elig-scope') syncEligScope();
  if(e.target.id==='n-dest') syncNotifDest();
  // The note under the Status dropdown says what the chosen value does to the
  // driver's app, so it has to follow the dropdown.
  if(e.target.id==='d-status') syncDriverStatusNote();
});
document.addEventListener('input',function(e){
  if(e.target.id==='orders-search') renderOrders();
  if(e.target.id==='dash-search') renderDashboard();
  if(e.target.id==='of-area') readOrderFilters();
  if(e.target.id==='drv-search'){ driverSearch=e.target.value.trim().toLowerCase(); renderDrivers(); }
  if(['q-items','q-service','q-delivery'].indexOf(e.target.id)>-1) syncQuoteTotal();
  if(e.target.id==='customers-search'){ customerSearch=e.target.value.trim(); renderCustomers(); }
  if(e.target.id==='overseas-search'){ overseasSearch=e.target.value.trim(); renderOverseas(); }
  if(['pr-bands','pr-overage','pr-packing'].indexOf(e.target.id)>-1) renderPricingPreview();
  if(e.target.id==='wipe-phrase'){ var g=$('wipe-go'); if(g) g.disabled=e.target.value.trim()!==WIPE_PHRASE; }
  if(e.target.id==='n-title'||e.target.id==='n-msg') updPhonePreview();
  if(e.target.id==='n-schedule') syncNotifSchedule();
  // (image URL paste removed — both photo fields are upload-only hidden inputs
  //  the dropzone writes to; nothing to sync on user input any more.)
  if(e.target.id==='m-emoji') syncEmojiSelection();
  // Paste a Maps link / "lat, lng" → fill the number fields (P5-06). Typing
  // directly in the number fields just refreshes the "location set" hint.
  if(e.target.id==='m-location') applyLocationPaste();
  if(e.target.id==='m-lat'||e.target.id==='m-lng') syncLocationHint();
  if(['pc-code','pc-disc','pc-valid','pc-start','pc-min','pc-maxdisc'].indexOf(e.target.id)>-1) updPromoPreview();
});
document.addEventListener('keydown',function(e){
  if(e.key==='Enter'&&(e.target.id==='l-email'||e.target.id==='l-pass')){ doLogin(); return; }
  if(e.key==='Enter'&&e.target.classList.contains('tab')){ e.target.click(); return; }
  if(e.key==='Escape'){
    if($('bell-menu')&&$('bell-menu').classList.contains('open')){ toggleBell(false); return; }
    if($('modal-confirm').classList.contains('open')){ settleConfirm(false); return; }
    var open=document.querySelector('.mbg.open');
    if(open){ closeModal(open.id); return; }
    if($('spanel').classList.contains('open')){ closeSidePanel(); return; }
    if($('sidebar').classList.contains('mob-open')){ closeMobileSidebar(); }
  }
});
// Chart tooltip
document.addEventListener('mouseover',function(e){
  var g=e.target.closest&&e.target.closest('.bar-g'); if(!g) return;
  var tip=$('chart-tip'), host=$('bar-chart'); if(!tip||!host) return;
  var svg=host.querySelector('svg'), scale=svg.clientWidth/svg.viewBox.baseVal.width;
  tip.textContent=g.getAttribute('data-label')+' · '+g.getAttribute('data-value')+' orders';
  tip.style.left=(Number(g.getAttribute('data-x'))*scale)+'px';
  tip.style.top=(Number(g.getAttribute('data-y'))*scale)+'px';
  tip.classList.add('show');
});
document.addEventListener('mouseout',function(e){
  if(e.target.closest&&e.target.closest('.bar-g')){ var tip=$('chart-tip'); if(tip) tip.classList.remove('show'); }
});
var resizeTimer=null;
window.addEventListener('resize',function(){
  clearTimeout(resizeTimer);
  resizeTimer=setTimeout(function(){ if($('page-analytics').classList.contains('active')) renderBarChart(); },160);
});

// ══════════════════════ INIT ══════════════════════
/* ── Mobile responsive tables ───────────────────────────────────────────────
   On phones the tables do NOT scroll sideways. The ≤720px CSS block folds each
   row into a stacked "COLUMN LABEL → value" card, which needs every <td> to
   carry its column name in data-label. Rows are re-rendered on every Firestore
   snapshot, so a MutationObserver re-stamps after each render. Setting an
   attribute is not a childList change, so this never re-triggers itself. Rows
   whose cell count ≠ header count (skeleton / colspan empty states) are skipped. */
/* Which columns stay visible while a phone row is collapsed, per tbody, by
   column INDEX. Everything else is folded behind the row's chevron.

   Chosen as "enough to recognise the record and judge whether to open it" — a
   name, one contact detail, and its state. A driver row printed all nine
   columns, which made one driver about a phone screen tall; the roster was
   unusable for the thing a roster is for, which is scanning.

   Indices, not header names: the headers are the label source and are already
   read positionally here, and a copy-editing change to a <th> should not
   silently collapse a column. A tbody absent from this map keeps every column
   visible. */
var MOBILE_PRIMARY={
  'orders-tbody':    [0,1,4,6],  // Order ID · Customer · Total · Status
  'dash-tbody':      [0,1,5,6],  // Order ID · Customer · Amount · Status
  // drivers-tbody removed — the Drivers roster is a card grid now (DV-1…DV-8).
  'merchants-tbody': [0,1,6],    // Merchant · Category · Status
  'customers-tbody': [0,1,7],    // Name · Email · Status
  'overseas-tbody':  [0,1,6],    // Ref · Customer · Status
  'promos-tbody':    [0,1,5]     // Code · Discount · Status
};

var _tblObservers=[];
function stampTableLabels(table){
  var ths=table.querySelectorAll('thead th');
  if(!ths.length) return;
  var labels=[]; for(var i=0;i<ths.length;i++){ labels.push(ths[i].textContent.trim()); }
  var body=table.querySelector('tbody');
  var primary=body?MOBILE_PRIMARY[body.id]:null;
  var rows=table.querySelectorAll('tbody tr');
  for(var r=0;r<rows.length;r++){
    var tds=rows[r].children;
    // Skeleton and empty-state rows use one colspan cell — nothing to label and
    // nothing to collapse.
    if(tds.length!==labels.length) continue;
    var firstHidden=true;
    for(var c=0;c<tds.length;c++){
      tds[c].setAttribute('data-label',labels[c]);
      if(!primary) continue;
      var hidden=primary.indexOf(c)===-1;
      tds[c].classList.toggle('mc-hide',hidden);
      // .mc-first carries the divider that separates summary from detail, so it
      // belongs to whichever hidden cell comes first — not to a fixed index.
      tds[c].classList.toggle('mc-first',hidden&&firstHidden);
      if(hidden) firstHidden=false;
    }
    if(primary) addRowExpander(rows[r]);
  }
}
/* The chevron lives inside the row's first cell but is positioned against the
   row, which is `display:block; position:relative` on phones. It cannot be its
   own <td>: that would change the cell count the labelling above depends on,
   and add a stray column to the desktop table. Hidden outside the phone
   breakpoint, where every column is on screen anyway. */
function addRowExpander(tr){
  if(tr.querySelector('.mc-exp')) return;
  var host=tr.children[0]; if(!host) return;
  var b=document.createElement('button');
  b.type='button';
  b.className='mc-exp';
  b.setAttribute('data-mc-exp','1');
  b.setAttribute('aria-expanded','false');
  b.setAttribute('aria-label','Show all details');
  b.title='Show all details';
  b.innerHTML=icon('caret-right');
  host.appendChild(b);
}
function toggleRowExpanded(btn){
  var tr=btn.closest('tr'); if(!tr) return;
  var open=!tr.classList.contains('mc-open');
  tr.classList.toggle('mc-open',open);
  btn.setAttribute('aria-expanded',open?'true':'false');
  btn.setAttribute('aria-label',open?'Hide extra details':'Show all details');
  btn.title=btn.getAttribute('aria-label');
}
function setupTableLabels(){
  if(_tblObservers.length) return; // wire up once
  var tables=document.querySelectorAll('.tbl-wrap table');
  for(var i=0;i<tables.length;i++){
    (function(t){
      var body=t.querySelector('tbody');
      if(!body) return;
      stampTableLabels(t);
      var mo=new MutationObserver(function(){ stampTableLabels(t); });
      mo.observe(body,{childList:true});
      _tblObservers.push(mo);
    })(tables[i]);
  }
}

function initApp(){
  $('tb-date').textContent=new Date().toLocaleDateString('en-JM',{weekday:'long',month:'long',day:'numeric'});
  renderDashboard(); renderOrders(); renderDrivers(); renderMerchants();
  renderPromos(); renderNotifHist(); renderAnalytics(); renderOverseas();
  updPromoPreview(); updPhonePreview(); renderEmojiPicker();
  fillNotifTagOptions(); syncNotifDest(); syncNotifSchedule();
  renderActivity();
  setupTableLabels();
  startListeners();
}

/* The panel is gated on the `admin` custom claim, not merely on being signed in.
   Firestore rules (isAdmin()) are the real trust boundary and already block every
   write, but customers and drivers share this Auth project, so without this check
   a non-admin who signs in would see the console shell and a wall of
   permission-denied toasts. We reject them cleanly instead. The claim is the same
   one the rules require, so any account that can actually administer already has
   it. */
function rejectNonAdmin(msg){
  signOut(auth);
  var errEl=$('l-err');
  if(errEl){
    errEl.innerHTML=icon('warning','ic-sm')+'<span>'+esc(msg)+'</span>';
    errEl.classList.add('show');
  }
}
onAuthStateChanged(auth,function(user){
  if(user){
    getIdTokenResult(user).then(function(res){
      if(!res.claims||res.claims.admin!==true){
        rejectNonAdmin('This account is not an administrator.');
        return;
      }
      $('login-page').style.display='none';
      $('app').style.display='block';
      /* Deliberately NOT the email address. This console is routinely open on a
         shared screen or in a screenshare, and the admin login address is half a
         credential; a display name is enough to confirm who is signed in. The
         email is still one click away in the account chip's title attribute for
         an admin who genuinely needs to check which account this is. */
      var label=user.displayName||'Admin';
      var anEl=document.querySelector('.an'); if(anEl) anEl.textContent=label;
      var abEl=document.querySelector('.ab');
      if(abEl) abEl.title='Signed in as '+(user.email||'an administrator');
      var avEl=document.querySelector('.av');
      if(avEl) avEl.textContent=(label[0]||'A').toUpperCase();
      initApp();
    }).catch(function(e){
      rejectNonAdmin('Could not verify administrator access: '+e.message);
    });
  }else{
    $('login-page').style.display='flex';
    $('app').style.display='none';
    stopListeners();
    orders=[]; drivers=[]; merchants=[]; promoCodes=[]; notifHistory=[]; customers=[]; inquiries=[];
    loadedOnce={orders:false,drivers:false,merchants:false,promos:false,notifs:false,
      customers:false,overseas:false};
    var btn=$('login-btn');
    if(btn){ btn.disabled=false; btn.innerHTML='Sign In'+icon('arrow-right'); }
    /* Signing out must not leave the next admin's password sitting on screen in
       plain text — the reveal is per-session, not a preference. */
    var pw=$('l-pass'); if(pw) pw.value='';
    togglePassReveal(false);
  }
});

initTheme();

// ── SETUP: Firebase Console → shipeast-1a1f6 → Authentication → Add user → admin@shipeast.com
// ── Collections: orders · drivers · merchants · promoCodes · notifications
