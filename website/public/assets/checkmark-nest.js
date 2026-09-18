(()=>{

const root=document.querySelector('.nest-animation');if(!root)return;const canvas=root.querySelector('canvas'),c=canvas.getContext('2d');if(!c)return;
const clamp=x=>Math.max(0,Math.min(1,x)),ease=x=>1-Math.pow(1-clamp(x),3);
function path(d,fill,stroke,width=1){const p=new Path2D(d);if(fill){c.fillStyle=fill;c.fill(p)}if(stroke){c.strokeStyle=stroke;c.lineWidth=width;c.stroke(p)}}
function ellipse(x,y,rx,ry,color){c.beginPath();c.ellipse(x,y,rx,ry,0,0,Math.PI*2);c.fillStyle=color;c.fill()}
function line(x,y,X,Y,color,w){c.beginPath();c.moveTo(x,y);c.lineTo(X,Y);c.strokeStyle=color;c.lineWidth=w;c.lineCap='round';c.stroke()}
function nest(front,t){c.save();c.translate(550,421);let bounce=t>3&&t<3.6?Math.sin((t-3)*16)*Math.exp(-(t-3)*5)*5:0;c.translate(0,bounce);c.lineJoin='round';
if(!front){c.shadowColor='#41352135';c.shadowBlur=22;c.shadowOffsetY=17;path('M -153 -130 Q -153 -148 -133 -148 L 133 -148 Q 153 -148 153 -128 L 153 128 Q 153 148 133 148 L -133 148 Q -153 148 -153 128 Z',null,'#946234',30);c.shadowColor='transparent';}
for(let i=0;i<17;i++){let o=(i-8)*1.55;let col=['#9b683b','#c49558','#e0b875','#b27b43','#edca8b'][i%5];if(!front){path(`M ${-149+o} 118 Q ${-158+o} -30 ${-149+o} -123 Q ${-148+o} ${-144+o} -126 ${-144+o} Q 8 ${-152+o} 126 ${-143+o} Q ${150+o} ${-141+o} ${150+o} -120 L ${149+o} 120`,null,col,2.5)}else{path(`M ${-151+o} 105 Q ${-151+o} ${144+o} -121 ${144+o} Q 0 ${157+o} 122 ${143+o} Q ${152+o} ${140+o} ${151+o} 104`,null,col,3)}}
for(let i=0;i<26;i++){let q=-125+i*10;if(front){line(q,136+Math.sin(i)*3,q+14,156+Math.sin(i)*3,i%2?'#8a592f':'#e8bd78',2)}else{line(-160,q,-139,q+13,'#e2b67b',2);line(140,q,160,q+13,'#a77743',2);line(q,-156,q+13,-136,'#a77743',2)}}
if(front){line(-144,138,-179,122,'#ac7b45',4);line(132,144,174,128,'#c79b60',4);line(87,155,117,171,'#b8884e',3)}c.restore()}
function feet(x,y,s,angle){c.save();c.translate(x,y);c.rotate(angle);c.scale(s,s);line(-23,95,-25,117,'#d39829',9);line(34,91,34,114,'#d39829',9);for(let x of [-25,34]){line(x,111,x-10,120,'#efb53c',6);line(x,111,x+9,119,'#efb53c',6)}c.restore()}
function bird(x,y,s,angle,flap,t){c.save();c.translate(x,y);c.rotate(angle);c.scale(s,s);c.lineJoin='round';
if(flap){let wing= Math.sin(t*23);c.save();c.translate(-16,0);c.rotate(wing*.65);path('M 0 18 Q -80 -12 -112 -75 Q -39 -73 20 -4 Z','#23934b','#14773c',3);c.restore()}
line(-23,95,-25,117,'#d39829',9);line(34,91,34,114,'#d39829',9);for(let x of [-25,34]){line(x,111,x-10,120,'#efb53c',6);line(x,111,x+9,119,'#efb53c',6)}
const d='M -116 -13 Q -126 -25 -114 -36 L -78 -63 Q -68 -71 -59 -61 L -13 -9 L 65 -145 Q 71 -155 84 -150 L 130 -129 Q 143 -123 136 -108 L 37 73 Q 13 113 -19 83 Z';
c.save();c.translate(5,9);path(d,'#176936');c.restore();let g=c.createLinearGradient(-85,-135,90,100);g.addColorStop(0,'#8ae476');g.addColorStop(.4,'#4bc85a');g.addColorStop(1,'#168b46');c.shadowColor='#154e3440';c.shadowBlur=8;c.shadowOffsetY=4;path(d,g,'#2a9a49',2);c.shadowColor='transparent';path('M -113 -30 L -77 -57 L -13 8 L 76 -139',null,'#aeec8870',4);
path('M 132 -113 Q 158 -101 159 -94 Q 151 -86 123 -86 Z','#eeb237','#c68a22',2);ellipse(105,-119,4.5,5,'#152b22');ellipse(121,-111,4,4.5,'#152b22');
if(flap){c.save();c.translate(1,13);c.rotate(Math.sin(t*23)*.8);path('M 0 0 Q -40 -42 -83 -34 Q -70 17 -8 31 Z','#35b752','#218e40',2);c.restore()}c.restore()}
function render(time){let t=Math.floor(time*12)/12;c.setTransform(1,0,0,1,0,0);c.clearRect(0,0,640,650);c.translate(-200,0);
ellipse(551,601,185,22,'#6b583316');nest(false,t);
let u=clamp((t-.5)/2.5),a=ease(u),x=340+210*a,y=324-175*Math.sin(u*Math.PI)+106*a,s=.72+.28*a,ang=(1-u)*.24+Math.sin(t*22)*(1-u)*.07;
if(t>3){let z=t-3;x=550;y=430+Math.sin(z*15)*Math.exp(-z*5)*18;ang=Math.sin(z*13)*Math.exp(-z*5)*.06}
ellipse(x,580,55*s,8*s,'#36573b18');bird(x,y,s,ang,t<3,t);nest(true,t);
// Feet grip the front of the rim instead of disappearing behind its weave.
feet(x,y,s,ang);
if(t>3.4&&t<4.2){let p=(t-3.4)/.8;c.globalAlpha=1-p;for(let i=0;i<3;i++){let xx=730+i*17,yy=293+i*30;line(xx,yy,xx+9+p*9,yy-12,'#b99a58',3)}c.globalAlpha=1}
}

const button=root.querySelector('button'),motion=matchMedia('(prefers-reduced-motion: reduce)');
const DURATION=8,SCENE_DURATION=4.5,clock={time:0};let flight=null,started=false;
const flock=document.createElement('div');flock.className='checkmark-flock';flock.hidden=true;flock.setAttribute('aria-hidden','true');document.body.append(flock);
const hasGSAP=Boolean(window.gsap&&window.MotionPathPlugin);if(hasGSAP)gsap.registerPlugin(MotionPathPlugin);
function finish(){if(flight){flight.kill();flight=null}flock.hidden=true;flock.replaceChildren();render(SCENE_DURATION);button.textContent='Replay flight';button.setAttribute('aria-label','Replay the checkmark bird and flock flight');}
function play(){
    finish();started=true;if(!hasGSAP||motion.matches)return;
    const FLOCK_DURATION=4.5,w=innerWidth,h=innerHeight,rect=canvas.getBoundingClientRect();
    const center=Math.max(h*.24,Math.min(h*.64,rect.top+rect.height*.35));
    const count=w<640?16:27,random=(min,max)=>min+Math.random()*(max-min);
    const limitY=y=>Math.max(48,Math.min(h-90,y));clock.time=0;flock.hidden=false;
    flight=gsap.timeline({onComplete:finish});
    flight.to(clock,{time:SCENE_DURATION,duration:DURATION,ease:'none',onUpdate:()=>render(clock.time)},0);
    // Loose shared groups provide cohesion; independent offsets keep the flock irregular.
    const groups=Array.from({length:4},()=>({height:random(-h*.17,h*.17),delay:random(.05,.95),bend:random(-70,70)}));
    for(let i=0;i<count;i++){
        const group=groups[Math.floor(random(0,groups.length))];
        const depth=Math.random(),size=(w<640?24:27)+depth*(w<640?24:34);
        const img=document.createElement('img');img.src=root.dataset.flockSrc;img.alt='';
        img.width=Math.round(size);img.height=Math.round(size);img.draggable=false;
        // Mid-distance birds stay sharp; distant and close birds soften.
        const blur=depth<.35?(.35-depth)*5:depth>.78?(depth-.78)*9:0;
        img.style.filter=`hue-rotate(${random(-20,20).toFixed(2)}deg) blur(${blur.toFixed(2)}px)`;
        img.style.zIndex=String(Math.round(depth*100));flock.append(img);
        const stray=i%6===0?random(-h*.13,h*.13):0;
        const y0=limitY(center+group.height+random(-65,65)+stray);
        const y1=limitY(y0+group.bend+random(-85,85));
        const y2=limitY(y0-group.bend*.6+random(-100,100));
        const y3=limitY(y0+random(-90,90));
        const startX=-size-random(20,w*.18),endX=w+size+30;
        const x1=w*random(.22,.36),x2=w*random(.60,.76);
        const delay=Math.max(0,Math.min(1.2,group.delay+random(-.25,.35)));
        // Stagger exits as well as entrances; the final bird clears with the nest scene.
        const end=i===count-1?FLOCK_DURATION:random(3.55,FLOCK_DURATION);
        const curve=`M ${startX} ${y0} C ${w*.04} ${y0+random(-35,35)} ${x1-w*.12} ${y1} ${x1} ${y1} S ${x2-w*.12} ${y2} ${x2} ${y2} S ${w*.95} ${y3} ${endX} ${y3}`;
        // The source GIF faces left; mirror it to face along the new left-to-right path.
        gsap.set(img,{x:startX,y:y0,scaleX:-1,opacity:.68+depth*.32,transformOrigin:'50% 50%'});
        flight.to(img,{duration:end-delay,ease:'sine.inOut',motionPath:{path:curve,autoRotate:true}},delay);
    }
    button.textContent='Pause flight';button.setAttribute('aria-label','Pause the checkmark bird and flock flight');
}
button.hidden=!hasGSAP;button.addEventListener('click',()=>{if(flight)finish();else play()});render(SCENE_DURATION);
const observer=new IntersectionObserver(entries=>{for(const entry of entries){if(entry.isIntersecting&&!started&&!motion.matches){play()}else if(!entry.isIntersecting&&flight){finish()}}},{threshold:.5});observer.observe(root);
motion.addEventListener('change',()=>{if(motion.matches)finish()});document.addEventListener('visibilitychange',()=>{if(document.hidden&&flight)finish()});window.addEventListener('resize',()=>{if(flight)finish()});
})();
