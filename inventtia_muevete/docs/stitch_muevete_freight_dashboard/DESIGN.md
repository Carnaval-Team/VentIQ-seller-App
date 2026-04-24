---
name: Kinetic Precision
colors:
  surface: '#f8f9ff'
  surface-dim: '#cbdbf5'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff4ff'
  surface-container: '#e5eeff'
  surface-container-high: '#dce9ff'
  surface-container-highest: '#d3e4fe'
  on-surface: '#0b1c30'
  on-surface-variant: '#44474d'
  inverse-surface: '#213145'
  inverse-on-surface: '#eaf1ff'
  outline: '#75777e'
  outline-variant: '#c5c6ce'
  surface-tint: '#4e5f7c'
  primary: '#00030a'
  on-primary: '#ffffff'
  primary-container: '#0a1d37'
  on-primary-container: '#7586a5'
  inverse-primary: '#b6c7e9'
  secondary: '#a04100'
  on-secondary: '#ffffff'
  secondary-container: '#fe6b00'
  on-secondary-container: '#572000'
  tertiary: '#000401'
  on-tertiary: '#ffffff'
  tertiary-container: '#00230d'
  on-tertiary-container: '#00994f'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d6e3ff'
  primary-fixed-dim: '#b6c7e9'
  on-primary-fixed: '#081c36'
  on-primary-fixed-variant: '#364763'
  secondary-fixed: '#ffdbcc'
  secondary-fixed-dim: '#ffb693'
  on-secondary-fixed: '#351000'
  on-secondary-fixed-variant: '#7a3000'
  tertiary-fixed: '#7efba4'
  tertiary-fixed-dim: '#61de8a'
  on-tertiary-fixed: '#00210c'
  on-tertiary-fixed-variant: '#005228'
  background: '#f8f9ff'
  on-background: '#0b1c30'
  surface-variant: '#d3e4fe'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  title-sm:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Work Sans
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 4px
  xs: 0.5rem
  sm: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  gutter: 16px
  margin: 24px
---

## Brand & Style

The design system is anchored in the concepts of reliability, momentum, and clarity. Designed for the high-stakes world of logistics and freight, the aesthetic balances the weight of corporate trust with the agility of modern tech. 

The visual direction follows a **Corporate / Modern** movement. It prioritizes high-legibility interfaces, structured card-based hierarchies, and a "utility-first" mindset. The emotional response is one of calm control—users should feel that their cargo is secure and their operations are moving efficiently. The interface avoids unnecessary decoration, using whitespace and precise alignment to signal professionalism and technological sophistication.

## Colors

The palette is engineered for trust and functional signaling. 

*   **Primary (Deep Navy):** Used for headers, navigation, and primary text to establish a foundation of stability and authority.
*   **Secondary (Vibrant Orange):** The "Movement" color. Reserved for primary calls to action, tracking indicators, and critical "In Transit" status updates.
*   **Tertiary (Success Green):** Utilized for "Delivered" statuses, verified badges, and secondary actions that signal completion.
*   **Neutrals:** A range of cool grays (Slate) provides the scaffolding for the interface, ensuring that the "White" background feels crisp and modern on both web and mobile screens.

## Typography

This design system utilizes **Inter** for its primary typeface due to its exceptional legibility on digital screens and its neutral, systematic character. It handles dense data tables and complex forms—common in logistics—without visual fatigue. 

**Work Sans** is introduced for labels and small metadata to provide a subtle structural contrast. Use the `label-caps` style for table headers and category tags to ensure clear information architecture. All headlines use tighter letter-spacing to maintain a modern, "tucked-in" professional look.

## Layout & Spacing

The layout philosophy relies on a **Fluid Grid** for web and a standard **Columnar Grid** for Android. 

*   **Web:** A 12-column system with 24px gutters. Content is housed within card containers that span logical column groups (e.g., 8 columns for a map view, 4 columns for shipment details).
*   **Mobile (Android):** A 4-column system with 16px margins. 

Spacing follows a strict 4px/8px baseline shift. Vertical rhythm is maintained by using `md` (24px) spacing between major sections and `xs` (8px) for related elements within a card.

## Elevation & Depth

Hierarchy is established through **Tonal Layers** and **Ambient Shadows**. This design system avoids heavy borders in favor of depth-based separation.

*   **Level 0 (Surface):** The main background uses a very light gray (#F8FAFC).
*   **Level 1 (Cards):** Pure white surfaces with a subtle, highly diffused shadow (0px 4px 12px rgba(10, 29, 55, 0.05)).
*   **Level 2 (Hover/Active):** A slightly more pronounced shadow (0px 8px 20px rgba(10, 29, 55, 0.10)) to indicate interactivity.
*   **Level 3 (Modals/Overlays):** Distinct elevation with a 20% backdrop blur on the layer beneath to keep the user focused on the immediate task.

## Shapes

The shape language is **Soft**, reflecting a balance between the rigid efficiency of a shipping container and the approachable nature of a modern service. 

Standard components like input fields and buttons use a 4px (0.25rem) corner radius. Cards and larger containers use the `rounded-lg` (8px) setting to provide a distinct visual frame that doesn't feel overly "bubbly" or informal.

## Components

### Buttons & Actions
*   **Primary Action:** High-contrast Vibrant Orange with white text. Slightly rounded corners.
*   **Secondary Action:** Deep Navy ghost buttons (outline only) for less urgent tasks.
*   **Status Chips:** Small, pill-shaped indicators using low-saturation versions of the action colors (e.g., light green background with dark green text for "Delivered").

### Cards
Cards are the primary container for shipment data. They must include a subtle 1px border (#E2E8F0) in addition to the Level 1 shadow to ensure definition on high-brightness mobile screens.

### Input Fields
Forms use a "Filled" style with a 2px bottom border that animates into a full outline on focus. This provides a clear affordance for data entry in high-speed environments.

### Logistics-Specific Components
*   **The Progress Tracker:** A vertical or horizontal stepper using the Primary Navy for completed steps and Vibrant Orange for the current active segment.
*   **Data Density:** Lists and tables should favor a compact "Density" mode, allowing dispatchers to see more shipments at once without scrolling.
*   **Iconography:** Use line-based, 2px stroke icons for clarity. Avoid filled icons except for active navigation states.