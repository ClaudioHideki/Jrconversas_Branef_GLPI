// Presentation-only pause for legacy entries; routes, flags and access stay intact.
// Remove a name from this set to restore its navigation entry.
const hiddenEntries = new Set(['Calls', 'Campaigns', 'Portals']);

export const navigationEntryVisible = (name, account) =>
  !hiddenEntries.has(name) &&
  !(account?.custom_attributes?.jrc_navigation?.hidden_entries || []).includes(
    name
  );

export const visibleSidebarSections = (sections, account) =>
  sections
    .map(section => ({
      ...section,
      items: section.items.filter(item =>
        navigationEntryVisible(item.name, account)
      ),
    }))
    .filter(section => section.items.length > 0);
