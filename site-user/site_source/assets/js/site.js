async function currentUser(){ const r=await fetch('/.auth/me'); if(!r.ok) return null; const j=await r.json(); return j.clientPrincipal || null; }
function userDisplayName(user){
  if(!user) return '';
  const claims = user.claims || [];
  const claim = (...types) => claims.find(item => types.includes(item.typ) || types.includes(item.type))?.val;
  return user.userDetails || claim('preferred_username','email','emails','upn','http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress') || user.userId || 'authenticated user';
}
async function requireUser(target){ const u=await currentUser(); const el=document.querySelector(target); if(el) el.textContent = u ? `Signed in as ${userDisplayName(u)}` : 'Not signed in'; return u; }
function showStatus(id,msg,isError=false){ const el=document.getElementById(id); if(!el) return; el.hidden=false; el.textContent=msg; el.className=isError?'status error':'status'; }
function escapeHtml(value){ return String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch])); }
