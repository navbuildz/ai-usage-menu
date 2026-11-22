# AI Usage Menu

## Brand direction: Aurora Gauge

This kit implements the selected dial plus three rising bars direction, based on the visual board provided for AI Usage Menu. This is a production-oriented vector recreation of that concept, not a pixel-perfect extraction of the AI-rendered artwork. Use the supplied original board as the visual source of truth.

**Product**: A free, MIT-licensed macOS menu bar app showing Claude Code and Codex plan usage, reset times and contributing usage. It reads from the tools signed in on a Mac. The app itself does not require account credentials, cookies or API keys.

**Position**: Your usage, at a glance. **Proof points**: Privacy by design, useful usage breakdowns, native Mac experience, and open source.

## Symbol concept

The open gauge shows headroom and limits. Three rising, softly rounded bars communicate usage across windows. The sweep from blue to pink to warm orange introduces an expressive personality without sacrificing functional clarity.

The mark exists as four families:

1. Full-color transparent mark for web, marketing and hero imagery.
2. Monochrome mark for small surfaces and accessibility.
3. Glossy dark app icon for macOS distribution and onboarding.
4. Small optimized template icon for the macOS menu bar.

## Core palette

| Token | Value | Role |
| --- | --- | --- |
| Violet | `#7C5CFF` | Primary CTA and highlighted controls |
| Orchid | `#BD6EFF` | Brand highlight and active tabs |
| Pink | `#FF7AA2` | Warm brand gradient and editorial accents |
| Cyan | `#4CC9FF` | Information accents and gradient |
| Blue | `#387BFF` | Cool gradient anchor |
| Mint | `#34D399` | Healthy usage state only |
| Amber | `#FFBB24` | Approaching limit state |
| Danger | `#FF5C8A` | Limit nearly exhausted |
| Background | `#0B0E20` | Dark-first canvas |
| Surface | `#15182C` | Dark UI card |
| Surface raised | `#1F233A` | Elevated card and hover |
| Border | `#343452` | Subtle dividers |
| Text | `#F6F7FF` | Primary copy in dark mode |
| Text secondary | `#A9AAC4` | Captions in dark mode |

**Important**: Usage status colors carry meaning. Use mint below 60 percent, amber from 60 through 84 percent, and danger from 85 percent and above as the starting defaults. These thresholds are configurable in the product. Do not use the marketing gradient as the functional status indication.

## Typography

**Mac app**: SF Pro provided by macOS. Use SF Mono or monospaced digits for percentages and counters. **Website**: Inter for display and UI headings, Source Sans 3 for body copy. These fonts are described rather than bundled. They can be loaded using normal font-hosting methods or use the declared system fallbacks.

| Role | Family | Weight | Notes |
| --- | --- | --- | --- |
| Marketing display | Inter | 700 to 800 | Tight tracking, generous line height |
| UI heading | Inter or SF Pro | 600 to 700 | Short, concrete labels |
| Body | Source Sans 3 or SF Pro | 400 to 500 | 15 to 17 px web default |
| Data | SF Mono or tabular system numerals | 600 to 700 | Avoid jitter as percentages change |

Font references:
- Inter: https://rsms.me/inter/
- Source Sans 3: https://fonts.google.com/specimen/Source+Sans+3
- SF Pro: macOS system font, see Apple typography documentation

## Logo use

Use the transparent **mark-gradient.svg** when the icon needs to live on any surface. Use **horizontal-dark-background.svg** over near-black or deep-blue surfaces. Use **horizontal-light-background.svg** over white or light surfaces. Do not place the full-color mark on very busy artwork without a solid local backdrop.

Clear space: at least the width of one short bar on all sides of the logo. Minimum recommended full-color mark: 32 px. For 16 to 24 px, use the optimized monochrome menu bar mark instead. Keep gradients within the logo itself. Avoid adding outlines, stretching the mark or recoloring individual bars arbitrarily.

## macOS app icon

The dark app icon is the primary shipping version. Light and tinted explorations are provided as alternatives. The `AppIcon.appiconset` contains PNG resolutions and an Xcode `Contents.json`. Test the 16, 32, 128 and 1024 px variants in Finder, Spotlight, Settings and the Mac app's About screen. The app is menu bar only and should not show a Dock tile during ordinary usage.

**Menu bar**: use the template image in `04-menu-bar`, not the glossy app icon. macOS should tint it automatically according to system appearance. Show the live usage percentage beside it. Red, amber and green are reserved for a separate health status cue.

## UI character

Dark is the hero appearance. Use deep navy panels, low-contrast violet borders, soft corner radii and restrained elevation. Aim for native macOS feel first. Cards should have a visible hierarchy: uppercase window name, large tabular percentage, clear reset count, and a status-colored progress bar. Use muted text for explanations. Light mode needs separate contrast checks rather than merely inverting colors.

## Icon language

UI icons use a 24 by 24 viewBox, 1.75 unit round strokes, round joins and a simple consistent grid. SVGs use `currentColor`. Use one accent at a time. The provider glyphs are generic technical symbols drawn for this product and not official logos or claims of affiliation.

## Brand voice

Friendly, precise, low friction. Lead with outcomes and verification. A good headline is **Know your AI usage. Stay in control.** A good supporting line is **See Claude Code and Codex usage, resets and what's contributing, right from your Mac menu bar.**

Avoid inflated claims, fake numbers and technical jargon in consumer-facing copy. Say **No cookies or API keys required** instead of **military-grade security**. Note the boundary precisely: Claude Code itself may make network requests when invoked, while AI Usage Menu does not initiate ordinary application traffic.

## Required attribution and footer

Always retain **From the makers of TypeFire** with a link to https://typefire.app on the site and in the menu bar app footer. Use the product disclaimer required in the implementation brief. This visual kit is branding for AI Usage Menu and does not include trademarked provider artwork.

## What this kit is and is not

All SVGs and colors in this package are editable assets. PNGs are exports from the vector artwork. The two product screenshot crops are **design concept references from the supplied board**, not captured screenshots of the actual built application or website. Replace them with real captures before launch. The original concept board is included under `07-reference-images`.
