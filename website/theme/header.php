<!doctype html>
<html <?php language_attributes(); ?>>
<head><meta charset="<?php bloginfo('charset'); ?>"><meta name="viewport" content="width=device-width, initial-scale=1"><script>try{const saved=localStorage.getItem('tt-theme');document.documentElement.dataset.theme=saved==='dark'||saved==='light'?saved:(matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light')}catch(e){document.documentElement.dataset.theme=matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'}</script><?php wp_head(); ?></head>
<body <?php body_class(); ?>><?php wp_body_open(); ?>
<a class="skip-link" href="#main">Skip to content</a>
<header class="site-header wrap">
    <a class="brand" href="<?php echo esc_url(home_url('/')); ?>"><img src="<?php echo tt_asset('app-icon.webp'); ?>" alt="" width="58" height="58"><span>Tracker Trapper</span></a>
    <nav aria-label="Main navigation"><button class="theme-toggle" type="button" aria-label="Toggle dark mode" aria-pressed="false" hidden>Dark mode</button><a href="<?php echo esc_url(home_url('/#how-it-works')); ?>">How it works</a><a href="<?php echo esc_url(home_url('/#help')); ?>">Help</a><a class="button small" href="<?php echo esc_url(home_url('/#download')); ?>">Get it free <?php tt_icon('arrow'); ?></a></nav>
</header>
