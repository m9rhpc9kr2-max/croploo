/**
 * Shared @font-face block for every server-rendered HTML page (status,
 * billing success/cancel, decision-log compliance export). Fonts are served
 * statically from /assets/fonts (see server.js) — the exact same Poppins /
 * JetBrains Mono files used by the PDF report generator, so every surface
 * in the app (Flutter, website, PDF, HTML pages) renders the same brand
 * fonts instead of each guessing at a system-font fallback stack.
 */
export const FONT_FACES = `
  @font-face { font-family: 'Poppins'; src: url('/assets/fonts/Poppins-Regular.ttf') format('truetype'); font-weight: 400; }
  @font-face { font-family: 'Poppins'; src: url('/assets/fonts/Poppins-Medium.ttf') format('truetype'); font-weight: 500; }
  @font-face { font-family: 'Poppins'; src: url('/assets/fonts/Poppins-SemiBold.ttf') format('truetype'); font-weight: 600; }
  @font-face { font-family: 'Poppins'; src: url('/assets/fonts/Poppins-Bold.ttf') format('truetype'); font-weight: 700; }
  @font-face { font-family: 'JetBrains Mono'; src: url('/assets/fonts/JetBrainsMono-Regular.ttf') format('truetype'); font-weight: 400; }
  @font-face { font-family: 'JetBrains Mono'; src: url('/assets/fonts/JetBrainsMono-Medium.ttf') format('truetype'); font-weight: 500; }
  @font-face { font-family: 'JetBrains Mono'; src: url('/assets/fonts/JetBrainsMono-SemiBold.ttf') format('truetype'); font-weight: 600; }
`;

export const FONT_UI = "'Poppins', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif";
export const FONT_DATA = "'JetBrains Mono', 'SF Mono', monospace";
