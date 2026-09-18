(()=>{
const perch=document.querySelector('.perch-friends');if(!perch||!window.gsap||!window.MotionPathPlugin)return;
gsap.registerPlugin(MotionPathPlugin);
const motion=matchMedia('(prefers-reduced-motion: reduce)');
const birds=[...perch.querySelectorAll('img')];
let departed=false,armed=false,timeline=null,initialY=scrollY;
function cleanup(){if(timeline)timeline.kill();timeline=null;}
function depart(){
 if(departed||motion.matches)return;
 const visible=birds.filter(el=>{const r=el.getBoundingClientRect();return getComputedStyle(el).display!=='none'&&r.bottom>0&&r.top<innerHeight});
 if(!visible.length)return;
 departed=true;timeline=gsap.timeline({onComplete:()=>{visible.forEach(el=>el.style.visibility='hidden');timeline=null}});
 visible.forEach((el,i)=>{
  const r=el.getBoundingClientRect(),distance=innerWidth-r.left+r.width+60;
  const rise=150+Math.random()*180,duration=5.5+Math.random()*1.5,delay=i*.13;
  // Animate the actual perched element from transform (0,0). Its containing
  // block never changes, so scrolling moves the bird and showcase together.
  const path=`M 0 0 C ${distance*.16} ${-rise*.7} ${distance*.64} ${-rise-50} ${distance} ${-rise}`;
  timeline.to(el,{duration,ease:'power1.inOut',motionPath:{path,autoRotate:false}},delay);
  timeline.to(el,{opacity:0,duration:.45,ease:'none'},delay+duration-.45);
 });
}
addEventListener('pointerdown',()=>{armed=true},{passive:true});
addEventListener('wheel',()=>{armed=true},{passive:true});
addEventListener('touchmove',()=>{armed=true},{passive:true});
addEventListener('keydown',e=>{if(['ArrowDown','ArrowUp','PageDown','PageUp',' ','Home','End'].includes(e.key))armed=true});
addEventListener('scroll',()=>{if(armed&&Math.abs(scrollY-initialY)>6)depart()},{passive:true});
setTimeout(()=>{initialY=scrollY},250);
motion.addEventListener('change',()=>{if(motion.matches){cleanup();gsap.set(birds,{clearProps:'transform,opacity,visibility'});departed=false}});
addEventListener('pagehide',cleanup);
})();
