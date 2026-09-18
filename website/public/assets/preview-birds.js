(() => {
  const area = document.querySelector('.preview-bird');
  if (!area) return;
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const random = (a, b) => a + Math.random() * (b - a);
  const birds = [...area.querySelectorAll('img')].map((el, i) => ({el, x: i ? .65 : .08, z: i ? .72 : .4, facing: i ? -1 : 1, jump: null, next: 0}));
  let visible = true, frame;
  const observer = new IntersectionObserver(([entry]) => {visible = entry.isIntersecting;});
  observer.observe(area);
  function draw(now) {
    const width = area.clientWidth, height = area.clientHeight;
    for (const bird of birds) {
      const size = bird.el.clientWidth;
      const maxX = Math.max(0, width - size - 12), maxY = Math.max(0, height - size - 12);
      let lift = 0;
      if (reduced.matches || !visible || document.hidden) {
        bird.jump = null; bird.next = now + random(400, 1400);
      } else {
        if (!bird.jump && now >= bird.next) {
          const targetX = random(0, 1), targetZ = random(.35, 1);
          // A fixed downward acceleration produces a ballistic takeoff and landing.
          const gravity = 1100;
          const peak = Math.min(random(36, 95), maxY * Math.min(bird.z, targetZ));
          const velocity = Math.sqrt(2 * gravity * peak);
          const duration = Math.max(.25, 2 * velocity / gravity);
          bird.facing = targetX < bird.x ? -1 : 1;
          bird.jump = {start: now, x: bird.x, z: bird.z, targetX, targetZ, velocity, gravity, duration};
        }
        if (bird.jump) {
          const j = bird.jump, elapsed = (now - j.start) / 1000;
          const t = Math.min(1, elapsed / j.duration);
          bird.x = j.x + (j.targetX - j.x) * t;
          bird.z = j.z + (j.targetZ - j.z) * t;
          lift = Math.max(0, j.velocity * elapsed - .5 * j.gravity * elapsed * elapsed);
          if (t === 1) {bird.jump = null; bird.next = now + random(300, 1800); lift = 0;}
        }
      }
      bird.el.style.transform = `translate(${6 + bird.x * maxX}px, ${6 + bird.z * maxY - lift}px) scaleX(${bird.facing})`;
      bird.el.style.zIndex = String(Math.round(bird.z * 100));
    }
    frame = requestAnimationFrame(draw);
  }
  frame = requestAnimationFrame(draw);
  addEventListener('pagehide', () => {cancelAnimationFrame(frame); observer.disconnect();});
  addEventListener('pageshow', event => {if (event.persisted) {observer.observe(area); frame = requestAnimationFrame(draw);}});
})();
