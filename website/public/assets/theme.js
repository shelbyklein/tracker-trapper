(()=>{
const root=document.documentElement,button=document.querySelector('.theme-toggle'),system=matchMedia('(prefers-color-scheme: dark)'),motion=matchMedia('(prefers-reduced-motion: reduce)');if(!button)return;
const label=button.querySelector('.theme-label'),bird=button.querySelector('.theme-nest-bird'),restingSrc=bird.getAttribute('src');
let timer=null;
function update(){const dark=root.dataset.theme==='dark',text=dark?'Switch to light mode':'Switch to dark mode';label.textContent=dark?'Light mode':'Dark mode';button.setAttribute('aria-label',text);button.title=text;button.setAttribute('aria-pressed',String(dark))}
function land(){clearTimeout(timer);timer=null;button.classList.remove('is-landing');bird.src=restingSrc}
button.hidden=false;update();button.addEventListener('click',()=>{
 land();
 root.dataset.theme=root.dataset.theme==='dark'?'light':'dark';
 try{localStorage.setItem('tt-theme',root.dataset.theme)}catch(e){}update();
 if(!motion.matches){
  bird.src=bird.dataset.flightSrc;
  // Restart cleanly if the user switches themes again during the landing.
  void button.offsetWidth;button.classList.add('is-landing');
  timer=setTimeout(land,760);
 }
});
motion.addEventListener('change',()=>{if(motion.matches)land()});
window.addEventListener('pagehide',land);
system.addEventListener('change',e=>{let saved;try{saved=localStorage.getItem('tt-theme')}catch(e){}if(!saved){root.dataset.theme=e.matches?'dark':'light';update()}});
})();
