# Crescendo Privacy Policy

This directory contains the Privacy Policy for the Crescendo mobile application, formatted for GitHub Pages.

## Files

- `index.html` - The privacy policy page (mobile-friendly, accessible HTML)

## GitHub Pages Setup

To publish this privacy policy:

1. **Enable GitHub Pages:**
   - Go to your repository Settings
   - Navigate to **Pages** (in the left sidebar)
   - Under "Source", select **Deploy from a branch**
   - Choose the branch (e.g., `main`) and folder (`/docs`)
   - Click **Save**

2. **Access the published page:**
   - After a few minutes, your privacy policy will be available at:
     ```
     https://[your-username].github.io/[repository-name]/privacy-policy/
     ```
   - For example: `https://adriannawenz.github.io/crescendo/privacy-policy/`

3. **Add to Google Play Console:**
   - Copy the full URL from step 2
   - Go to Google Play Console → Your App → Store presence → Privacy policy
   - Paste the URL into the "Privacy policy" field
   - Save changes

## Updating the Policy

To update the privacy policy:

1. Edit `index.html`
2. Update the "Last updated" date
3. Commit and push changes
4. GitHub Pages will automatically rebuild (may take a few minutes)

## Notes

- The privacy policy is designed to meet Google Play's requirements for apps using `RECORD_AUDIO` permission
- No analytics, cookies, or tracking are included
- The page is fully static (HTML + CSS only, no JavaScript)
- Mobile-friendly and accessible design
