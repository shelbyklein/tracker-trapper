(()=>{
const root=document.documentElement,button=document.querySelector('.theme-toggle'),system=matchMedia('(prefers-color-scheme: dark)'),motion=matchMedia('(prefers-reduced-motion: reduce)');if(!button)return;
const label=button.querySelector('.theme-label'),bird=button.querySelector('.theme-nest-bird');
let flight=null,layer=null;
const color=theme=>theme==='dark'?'hue-rotate(110deg)':'none';
function update(){const dark=root.dataset.theme==='dark',text=dark?'Switch to light mode':'Switch to dark mode';label.textContent=dark?'Light mode':'Dark mode';button.setAttribute('aria-label',text);button.title=text;button.setAttribute('aria-pressed',String(dark));bird.style.filter=color(root.dataset.theme)}
function land(){if(flight)flight.kill();flight=null;if(layer)layer.remove();layer=null;bird.style.visibility='';button.classList.remove('is-landing');update()}
function animate(previous){
 if(motion.matches||!window.gsap||!window.MotionPathPlugin)return;
 gsap.registerPlugin(MotionPathPlugin);
 const r=bird.getBoundingClientRect(),w=r.width,h=r.height;
 layer=document.createElement('div');layer.className='theme-flight-layer';layer.setAttribute('aria-hidden','true');document.body.append(layer);
 function flyer(filter,x,y){const img=document.createElement('img');img.src=bird.dataset.flightSrc;img.alt='';img.width=w;img.height=h;img.style.filter=filter;layer.append(img);gsap.set(img,{x,y});return img}
 const outgoing=flyer(color(previous),r.left,r.top);
 // The arriving bird starts inside the viewport, so the flock never disappears.
 const startX=Math.min(innerWidth-w-6,r.left+125),startY=r.top+100;
 const incoming=flyer(color(root.dataset.theme),startX,startY);
 const red=flyer('hue-rotate(245deg)',Math.min(innerWidth-w-6,r.left+60),r.top+140);
 bird.style.visibility='hidden';button.classList.add('is-landing');
 flight=gsap.timeline({onComplete:land});
 flight.to(outgoing,{duration:1.25,ease:'power1.in',motionPath:{path:`M ${r.left} ${r.top} Q ${r.left*.55} ${r.top+85} ${-w-30} ${r.top+35}`,autoRotate:false}},0);
 flight.to(red,{duration:1.7,ease:'sine.inOut',motionPath:{path:`M ${Math.min(innerWidth-w-6,r.left+60)} ${r.top+140} Q ${r.left*.5} ${r.top+30} ${-w-40} ${r.top+110}`,autoRotate:false}},0);
 flight.to(incoming,{duration:1.85,ease:'power2.out',motionPath:{path:`M ${startX} ${startY} C ${startX-65} ${Math.max(3,r.top-25)} ${r.left-65} ${Math.max(3,r.top-25)} ${r.left} ${r.top}`,autoRotate:false}},0);
}
button.hidden=false;update();button.addEventListener('click',()=>{
 land();const previous=root.dataset.theme;root.dataset.theme=previous==='dark'?'light':'dark';
 try{localStorage.setItem('tt-theme',root.dataset.theme)}catch(e){}update();animate(previous);
});
motion.addEventListener('change',()=>{if(motion.matches)land()});
window.addEventListener('pagehide',land);window.addEventListener('resize',land);window.addEventListener('scroll',()=>{if(flight)land()},{passive:true});
document.addEventListener('visibilitychange',()=>{if(document.hidden)land()});
system.addEventListener('change',e=>{let saved;try{saved=localStorage.getItem('tt-theme')}catch(e){}if(!saved){land();root.dataset.theme=e.matches?'dark':'light';update()}});
})();
