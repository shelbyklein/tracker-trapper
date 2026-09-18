(()=>{
const perch=document.querySelector('.perch-friends');if(!perch||!window.gsap||!window.MotionPathPlugin)return;
gsap.registerPlugin(MotionPathPlugin);
const motion=matchMedia('(prefers-reduced-motion: reduce)');
const birds=[...perch.querySelectorAll('img')];
const restingSources=new Map(birds.map(el=>[el,el.getAttribute('src')]));
const flightImage=new Image();flightImage.src=perch.dataset.flightSrc;
let departed=false,armed=false,timeline=null,initialY=scrollY;
function cleanup(){if(timeline)timeline.kill();timeline=null;}
function depart(){
 if(departed||motion.matches)return;
 const visible=birds.filter(el=>{const r=el.getBoundingClientRect();return getComputedStyle(el).display!=='none'&&r.bottom>0&&r.top<innerHeight});
 if(!visible.length)return;
 departed=true;timeline=gsap.timeline({onComplete:()=>{visible.forEach(el=>el.style.visibility='hidden');timeline=null}});
 const escapeLeft=Math.random()<.5;
 visible.forEach((el,i)=>{
  const r=el.getBoundingClientRect();
  // Fan out to both sides, with independent timing, climb and banking.
  const direction=(i%2===0?-1:1)*(escapeLeft?-1:1);
  const distance=direction<0?-(r.right+r.width+80):innerWidth-r.left+r.width+80;
  const rise=100+Math.random()*Math.min(innerHeight*.55,420);
  const duration=1.5+Math.random()*.9,delay=Math.random()*.22;
  const bend=.18+Math.random()*.24,bank=direction*(8+Math.random()*16);
  // Keep the same element and containing block so takeoff stays on the perch.
  timeline.set(el,{attr:{src:perch.dataset.flightSrc},scaleX:direction<0?1:-1},delay);
  const path=`M 0 0 C ${distance*.12} ${-40-Math.random()*90} ${distance*bend} ${-rise*.8} ${distance} ${-rise}`;
  timeline.to(el,{duration,ease:'power1.in',motionPath:{path,autoRotate:false}},delay);
  timeline.to(el,{rotation:bank,duration:duration*.4,ease:'sine.out'},delay);

 });
}
addEventListener('pointerdown',()=>{armed=true},{passive:true});
addEventListener('wheel',()=>{armed=true},{passive:true});
addEventListener('touchmove',()=>{armed=true},{passive:true});
addEventListener('keydown',e=>{if(['ArrowDown','ArrowUp','PageDown','PageUp',' ','Home','End'].includes(e.key))armed=true});
addEventListener('scroll',()=>{if(armed&&Math.abs(scrollY-initialY)>6)depart()},{passive:true});
setTimeout(()=>{initialY=scrollY},250);
motion.addEventListener('change',()=>{if(motion.matches){cleanup();birds.forEach(el=>el.setAttribute('src',restingSources.get(el)));gsap.set(birds,{clearProps:'transform,opacity,visibility'});departed=false}});
addEventListener('pagehide',cleanup);
})();
