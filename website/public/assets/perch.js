(()=>{
const perch=document.querySelector('.perch-friends');if(!perch||!window.gsap||!window.MotionPathPlugin)return;
gsap.registerPlugin(MotionPathPlugin);const motion=matchMedia('(prefers-reduced-motion: reduce)');let departed=false,armed=false,timeline=null,layer=null;let initialY=scrollY;
const birds=[document.querySelector('.hero-bird'),...perch.querySelectorAll('img')].filter(Boolean);
function cleanup(){if(timeline)timeline.kill();timeline=null;if(layer)layer.remove();layer=null;}
function depart(){if(departed||motion.matches)return;departed=true;
 const visible=birds.map(el=>({el,r:el.getBoundingClientRect()})).filter(({el,r})=>getComputedStyle(el).display!=='none'&&r.bottom>0&&r.top<innerHeight);
 if(!visible.length){departed=false;return}layer=document.createElement('div');layer.className='checkmark-flock';layer.setAttribute('aria-hidden','true');document.body.append(layer);
 timeline=gsap.timeline({onComplete:cleanup});
 visible.forEach(({el,r},i)=>{const img=document.createElement('img');img.src=perch.dataset.flightSrc;img.alt='';img.style.filter=getComputedStyle(el).filter;img.width=r.width;img.height=r.height;layer.append(img);el.style.visibility='hidden';
 const y=Math.max(25,r.top),endY=Math.max(20,y-120-Math.random()*150),endX=innerWidth+r.width+50;
 gsap.set(img,{x:r.left,y,scaleX:-1});
 const path=`M ${r.left} ${y} C ${r.left+80} ${Math.max(10,y-90)} ${innerWidth*.8} ${endY+70} ${endX} ${endY}`;
 timeline.to(img,{duration:5.5+Math.random()*1.5,ease:'power1.inOut',motionPath:{path,autoRotate:true}},i*.10);
 });
}
// Arm only on intentional scrolling, not anchor restoration or initial page layout.
addEventListener('pointerdown',()=>{armed=true},{passive:true});
addEventListener('wheel',()=>{armed=true},{passive:true});addEventListener('touchmove',()=>{armed=true},{passive:true});addEventListener('keydown',e=>{if(['ArrowDown','ArrowUp','PageDown','PageUp',' ','Home','End'].includes(e.key))armed=true});
addEventListener('scroll',()=>{if(armed&&Math.abs(scrollY-initialY)>6)depart()},{passive:true});
setTimeout(()=>{initialY=scrollY},250);
motion.addEventListener('change',()=>{if(motion.matches){cleanup();birds.forEach(el=>el.style.visibility='')}});
addEventListener('pagehide',cleanup);
})();
