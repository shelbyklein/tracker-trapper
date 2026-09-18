<?php get_header(); ?>
<main id="main">
<section class="hero wrap" aria-labelledby="hero-heading">
    <div class="hero-copy"><h1 id="hero-heading">Keep the vibe.<br>Track the work.</h1><p class="hero-description">Your agents are building. Stay in the loop.</p><div class="hero-action"><a class="button" href="#download"><?php tt_icon('download'); ?> Get Tracker Trapper free</a><span class="compatibility">For Mac · Codex + Claude Code</span></div></div>
    <div class="hero-notes" aria-hidden="true"><span class="hand good-ideas">Good ideas<br>ship faster<span class="hand-arrow">↳</span></span><span class="sticky hand">Small steps<br><b>Big things</b></span></div>
</section>
<section class="showcase wrap" aria-label="See Tracker Trapper in action">
    <div class="showcase-surface"></div>
    <img class="hero-bird" src="<?php echo tt_asset('bird-green.webp'); ?>" alt="" width="1024" height="1024" fetchpriority="high">
    <div class="perch-friends" aria-hidden="true" data-flight-src="<?php echo tt_asset('checkmark-flock.gif'); ?>"><?php for ($i = 0; $i < 5; $i++) : ?><img class="perch-bird perch-bird-<?php echo $i; ?>" src="<?php echo tt_asset('bird-green.webp'); ?>" alt="" width="1024" height="1024"><?php endfor; ?></div>
    <div class="seal" aria-hidden="true"><span>Your next<br>move,<br>visible.</span></div>
    <div class="showcase-intro" aria-hidden="true"><span class="hand">From issues<br>to progress <span class="intro-arrow">↴</span></span><span class="hand same-thread">Same thread.<br>More progress.</span></div>
    <div class="screens">
    <?php foreach (['working' => 'Working', 'waiting' => 'Needs you', 'complete' => 'Complete'] as $state => $label) : ?>
        <figure class="screen screen-<?php echo esc_attr($state); ?>">
            <figcaption><span>0<?php echo $state === 'working' ? '1' : ($state === 'waiting' ? '2' : '3'); ?></span> / <?php echo esc_html($label); ?></figcaption>
            <div class="menubar" aria-hidden="true"><span class="menu-mark"><?php tt_icon('check'); ?></span><?php tt_icon('wifi'); ?><span class="battery"></span><span class="menu-time">Mon 9:41 AM</span></div>
            <div class="glass-panel">
                <div class="panel-header"><strong>Tracker Trapper</strong><span class="panel-tools" aria-hidden="true"><?php tt_icon('gear'); ?><span class="bell"><?php tt_icon('bell'); ?><?php if ($state === 'waiting') : ?><i>1</i><?php endif; ?></span><span>Refresh</span></span></div>
                <?php if ($state === 'waiting') : ?><div class="notification"><span class="status orange">!</span><div><strong>Waiting for your input</strong><span>Which email should receive the form?</span></div></div><?php endif; ?>
                <div class="issue-card <?php echo $state === 'complete' ? 'celebration' : ''; ?>">
                <?php if ($state === 'complete') : ?>
                    <div class="confetti" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div><span class="party" aria-hidden="true">🎉</span><h3>Issue complete!</h3><span class="repo">studio/side-project #24</span><p>Build the landing page</p><ul class="done-list"><li><?php tt_icon('check'); ?><s>Add the contact form</s></li><li><?php tt_icon('check'); ?><s>Check mobile layout</s></li><li><?php tt_icon('check'); ?><s>Review the finished page</s></li></ul>
                <?php else : ?>
                    <div class="repo-row"><span class="repo">studio/side-project #24</span><?php tt_icon('link'); ?></div><h3>Build the landing page</h3><div class="progress-label"><span>2/5 complete</span><span>40%</span></div><div class="progress-track" role="img" aria-label="2 of 5 tasks complete"><span></span></div>
                    <ul class="task-list"><li><span class="status <?php echo $state === 'working' ? 'spinner' : 'orange'; ?>"><?php echo $state === 'waiting' ? '!' : ''; ?></span>Add the contact form</li><li><span class="status next"></span>Check mobile layout</li><li><span class="status empty"></span>Review the finished page</li></ul>
                    <div class="agent"><span class="dot <?php echo $state === 'waiting' ? 'amber' : ''; ?>"></span>Codex · <?php echo $state === 'working' ? 'Active' : 'Waiting for input'; ?></div><span class="activity">Activity updated just now</span>
                <?php endif; ?>
                </div>
                <div class="panel-footer">Synced or no pending updates.</div>
            </div>
        </figure>
    <?php endforeach; ?>
    </div>
    <div class="showcase-bottom"><p>Illustrative product screens</p><span class="hand" aria-hidden="true">Clearer context.<br>Happier you. ↗</span></div>
</section>
<section id="how-it-works" class="benefits wrap" aria-label="Why Tracker Trapper">
    <article><span class="benefit-icon"><?php tt_icon('alert'); ?></span><div><h2>Catch the blockers.</h2><p>Spot what’s stuck before<br class="desktop-break"> it slows you down.</p></div></article>
    <article><span class="benefit-icon blue"><?php tt_icon('list'); ?></span><div><h2>See what’s next.</h2><p>Follow your agents’ progress<br class="desktop-break"> at a glance.</p></div></article>
    <article><span class="benefit-icon"><?php tt_icon('smile'); ?></span><div><h2>Enjoy the progress.</h2><p>Less context switching.<br class="desktop-break"> More building.</p></div></article>
</section>
<section id="download" class="download wrap" aria-labelledby="download-heading">
    <figure class="nest-animation" data-flock-src="<?php echo tt_asset('checkmark-flock.gif'); ?>"><canvas width="640" height="650" role="img" aria-label="A green checkmark bird lands in a woven square nest, completing the checkbox.">A green checkmark bird in a woven checkbox nest.</canvas><figcaption><span class="hand">A little flight. A job done.</span><button type="button" hidden>Replay flight</button></figcaption><noscript><style>.nest-animation canvas,.nest-animation figcaption{display:none}</style><img src="<?php echo tt_asset('checkmark-nest-poster.png'); ?>" alt="Green checkmark bird perched in a woven checkbox nest" width="960" height="720"></noscript></figure>
    <div class="download-copy"><h2 id="download-heading">Big ideas.<br>Fewer lost threads.</h2><p>A little menu-bar companion for your next big thing.</p><a class="button" href="https://github.com/shelbyklein/tracker-trapper/archive/refs/heads/main.zip"><?php tt_icon('download'); ?> Download free source</a><a class="guide-link" href="https://github.com/shelbyklein/tracker-trapper/blob/main/docs/mac-guide.md">Mac setup guide <?php tt_icon('arrow'); ?></a><p class="release-note">Available from source for macOS 13+. A packaged installer is coming later.</p></div>
</section>
<section id="help" class="help wrap" aria-labelledby="help-heading"><div class="help-intro"><span class="eyebrow">A few things to know</span><h2 id="help-heading">Small app.<br>Clear expectations.</h2></div><div class="questions"><details><summary>How do I get started?<span>+</span></summary><p>Build the app using the <a href="https://github.com/shelbyklein/tracker-trapper/blob/main/docs/mac-guide.md">Mac setup guide</a>, connect your agent through the local MCP server, and import a GitHub issue checklist. The guide walks you through each step. The current release needs a Swift 6 toolchain, Git, GitHub CLI, and jq.</p></details><details><summary>Does it work with my coding agent?<span>+</span></summary><p>Tracker Trapper supports reporting workflows for Codex and Claude Code. Connect the integration and give your agent the reporting instructions so its progress appears in the menu bar. It doesn’t automatically follow every conversation.</p></details><details><summary>What does it track?<span>+</span></summary><p>Your registered GitHub issue checklists, reported task progress, blockers, and what comes next. Progress is stored locally on your Mac. GitHub synchronization is an explicit step in the current workflow.</p></details><details><summary>Is it really free?<span>+</span></summary><p>Yes. You can download the source for free. There’s no Tracker Trapper subscription. Your coding tools and their accounts are separate.</p></details></div></section>
</main>
<?php get_footer(); ?>
