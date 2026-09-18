(()=>{
const root=document.documentElement,button=document.querySelector('.theme-toggle'),system=matchMedia('(prefers-color-scheme: dark)');if(!button)return;
function update(){const dark=root.dataset.theme==='dark';button.textContent=dark?'Light mode':'Dark mode';button.setAttribute('aria-label',dark?'Switch to light mode':'Switch to dark mode');button.setAttribute('aria-pressed',String(dark))}
button.hidden=false;update();button.addEventListener('click',()=>{root.dataset.theme=root.dataset.theme==='dark'?'light':'dark';try{localStorage.setItem('tt-theme',root.dataset.theme)}catch(e){}update()});system.addEventListener('change',e=>{let saved;try{saved=localStorage.getItem('tt-theme')}catch(e){}if(!saved){root.dataset.theme=e.matches?'dark':'light';update()}});
})();
