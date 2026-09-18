(()=>{
const perch=document.querySelector('.perch-friends');if(!perch||!window.gsap||!window.MotionPathPlugin)return;
gsap.registerPlugin(MotionPathPlugin);
const motion=matchMedia('(prefers-reduced-motion: reduce)');
const birds=[...perch.querySelectorAll('img')];
// Keep a mixed flock even when only two companions fit on mobile.
const firstDirection=Math.random()<.5?-1:1;
const directions=new Map(birds.map((el,i)=>[el,(i%2===0?1:-1)*firstDirection]));
function facePerch(){birds.forEach(el=>gsap.set(el,{scaleX:directions.get(el)}))}
facePerch();
const restingSources=new Map(birds.map(el=>[el,el.getAttribute('src')]));
const flightImage=new Image();flightImage.src=perch.dataset.flightSrc;
let departed=false,armed=false,timeline=null,initialY=scrollY;
function cleanup(){if(timeline)timeline.kill();timeline=null;}
function depart(){
 if(departed||motion.matches)return;
 const visible=birds.filter(el=>{const r=el.getBoundingClientRect();return getComputedStyle(el).display!=='none'&&r.bottom>0&&r.top<innerHeight});
 if(!visible.length)return;
 departed=true;timeline=gsap.timeline({onComplete:()=>{visible.forEach(el=>el.style.visibility='hidden');timeline=null}});
 visible.forEach(el=>{
  const r=el.getBoundingClientRect();
  // Fan out to both sides, with independent timing, climb and banking.
  const direction=directions.get(el);
  const distance=direction<0?-(r.right+r.width+80):innerWidth-r.left+r.width+80;
  const rise=100+Math.random()*Math.min(innerHeight*.55,420);
  const duration=1.5+Math.random()*.9,delay=Math.random()*.22;
  const bend=.18+Math.random()*.24,bank=direction*(8+Math.random()*16);
  // Keep the same element and containing block so takeoff stays on the perch.
  timeline.set(el,{attr:{src:perch.dataset.flightSrc},scaleX:-direction},delay);
  const path=`M 0 0 C ${distance*.12} ${-40-Math.random()*90} ${distance*bend} ${-rise*.8} ${distance} ${-rise}`;
  timeline.to(el,{duration,ease:'power1.in',motionPath:{path,autoRotate:false}},delay);
  timeline.to(el,{rotation:bank,duration:duration*.4,ease:'sine.out'},delay);

 });
}
// The big bird stays on the ledge: short hops, a soft landing, then a pause.
const hero=document.querySelector('.hero-bird');
if(hero){
 let hop=null,rest=null,inView=false;
 function stopHopping(){
  if(rest)rest.kill();if(hop)hop.kill();rest=null;hop=null;
  gsap.set(hero,{clearProps:'transform,transformOrigin'});
 }
 function scheduleHop(){
  if(motion.matches||document.hidden||!inView)return;
  rest=gsap.delayedCall(1.8+Math.random()*3,()=>{
   rest=null;
   const width=hero.getBoundingClientRect().width;
   const current=Number(gsap.getProperty(hero,'x'))||0;
   // Stay close to the original perch, including on narrow screens.
   const target=current < -width*.16 ? 0 : -width*(.2+Math.random()*.14);
   const height=width*(.055+Math.random()*.035);
   hop=gsap.timeline({onComplete:()=>{hop=null;scheduleHop()}});
   hop.set(hero,{transformOrigin:'50% 90%'})
    .to(hero,{scaleY:.94,scaleX:1.035,duration:.12,ease:'power1.in'})
    .to(hero,{x:target,duration:.42,ease:'sine.inOut'},'takeoff')
    .to(hero,{y:-height,scaleY:1.025,scaleX:.985,duration:.2,ease:'power2.out'},'takeoff')
    .to(hero,{y:0,scaleY:.95,scaleX:1.025,duration:.22,ease:'power2.in'},'takeoff+=0.2')
    .to(hero,{scaleX:1,scaleY:1,duration:.16,ease:'sine.out'});
  });
 }
 function resume(){stopHopping();scheduleHop()}
 const observer=new IntersectionObserver(entries=>{
  inView=entries[0].isIntersecting;resume();
 },{threshold:.25});
 observer.observe(hero);
 motion.addEventListener('change',resume);
 document.addEventListener('visibilitychange',resume);
 addEventListener('resize',resume);
 addEventListener('pagehide',stopHopping);
 addEventListener('pageshow',resume);
}
addEventListener('pointerdown',()=>{armed=true},{passive:true});
addEventListener('wheel',()=>{armed=true},{passive:true});
addEventListener('touchmove',()=>{armed=true},{passive:true});
addEventListener('keydown',e=>{if(['ArrowDown','ArrowUp','PageDown','PageUp',' ','Home','End'].includes(e.key))armed=true});
addEventListener('scroll',()=>{if(armed&&Math.abs(scrollY-initialY)>6)depart()},{passive:true});
setTimeout(()=>{initialY=scrollY},250);
motion.addEventListener('change',()=>{if(motion.matches){cleanup();birds.forEach(el=>el.setAttribute('src',restingSources.get(el)));gsap.set(birds,{clearProps:'transform,opacity,visibility'});facePerch();departed=false}});
addEventListener('pagehide',cleanup);
})();
