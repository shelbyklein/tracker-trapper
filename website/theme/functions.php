<?php
/** Tracker Trapper — local, self-contained landing-page theme. */
if (!defined('ABSPATH')) { exit; }
add_action('after_setup_theme', function () {
    add_theme_support('title-tag');
    add_theme_support('post-thumbnails');
    add_theme_support('html5', ['search-form', 'gallery', 'caption', 'style', 'script']);
});
add_action('wp_enqueue_scripts', function () {
    if (is_front_page()) {
        wp_enqueue_script('tt-gsap', get_template_directory_uri() . '/assets/gsap.min.js', [], '3.13.0', true);
        wp_enqueue_script('tt-motion-path', get_template_directory_uri() . '/assets/MotionPathPlugin.min.js', ['tt-gsap'], '3.13.0', true);
        wp_enqueue_script('tt-perch', get_template_directory_uri() . '/assets/perch.js', ['tt-motion-path'], filemtime(get_template_directory() . '/assets/perch.js'), true);
        wp_enqueue_script('tracker-trapper-nest', get_template_directory_uri() . '/assets/checkmark-nest.js', ['tt-motion-path'], filemtime(get_template_directory() . '/assets/checkmark-nest.js'), true); }
    wp_enqueue_script('tt-theme', get_template_directory_uri() . '/assets/theme.js', [], filemtime(get_template_directory() . '/assets/theme.js'), true);
    wp_enqueue_style('tracker-trapper', get_stylesheet_uri(), [], filemtime(get_stylesheet_directory() . '/style.css'));
});
add_action('wp_head', function () {
    if (is_front_page()) {
        echo '<meta name="description" content="Keep the vibe. Track the work. Tracker Trapper is a free Mac menu-bar companion for GitHub checklists and coding-agent progress.">';
    }
    echo '<link rel="icon" href="' . esc_url(get_template_directory_uri() . '/assets/app-icon.webp') . '">';
});
function tt_asset($name) { return esc_url(get_template_directory_uri() . '/assets/' . $name); }
function tt_icon($name, $class = '') {
    $paths = [
        'arrow' => '<path d="M5 12h14M13 6l6 6-6 6"/>',
        'check' => '<path d="m5 12 4 4L19 6"/>',
        'list' => '<path d="M9 6h11M9 12h11M9 18h11"/><path d="M3 6h1M3 12h1M3 18h1"/>',
        'alert' => '<path d="m12 3 10 18H2L12 3Z"/><path d="M12 9v5M12 17v.2"/>',
        'smile' => '<circle cx="12" cy="12" r="9"/><path d="M8 14s1 3 4 3 4-3 4-3M8 8v1M16 8v1"/>',
        'link' => '<path d="M14 3h7v7M21 3 10 14M10 4H4v16h16v-6"/>',
        'bell' => '<path d="M5 17h14l-2-4V9a5 5 0 0 0-10 0v4l-2 4ZM10 21h4"/>',
        'gear' => '<circle cx="12" cy="12" r="4"/><path d="m9 2 6 0 1 3 3 1 3 3v6l-3 1-1 3-3 3H9l-1-3-3-1-3-3V9l3-1 1-3 3-3Z"/>',
        'download' => '<path d="M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5"/>',
        'wifi' => '<path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M9 16a5 5 0 0 1 6 0M12 20h.01"/>',
    ];
    echo '<svg class="icon ' . esc_attr($class) . '" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . ($paths[$name] ?? $paths['check']) . '</svg>';
}
