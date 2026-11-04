import { describe, expect, it } from 'vitest';
import {
  glpiScreen,
  usesGlpiScreen,
  operationBlock,
  operationAttributes,
  operationFamily,
} from '../helpers/glpiScreens';

describe('GLPI screen and operation contracts', () => {
  it('selects the backend primary source only and leaves JRC configuration local', () => {
    expect(usesGlpiScreen({ data_source: 'native' }, 'tickets')).toBe(false);
    expect(usesGlpiScreen({}, 'tickets')).toBe(false);
    expect(usesGlpiScreen({ data_source: 'glpi' }, 'edit')).toBe(true);
    expect(usesGlpiScreen({ data_source: 'glpi' }, 'settings')).toBe(false);
    expect(usesGlpiScreen({ data_source: 'glpi' }, 'categories')).toBe(false);
  });
  it.each([
    'overview',
    'tickets',
    'mine',
    'tasks',
    'approvals',
    'problems',
    'changes',
    'knowledge',
    'documents',
    'sla',
    'reports',
  ])('has a remote screen for %s', screen => {
    expect(glpiScreen(screen)).not.toBeNull();
  });
  it('keeps incident tickets distinct from problems', () => {
    expect(glpiScreen('incidents')).toEqual({
      kind: 'tickets',
      filters: { type: 1 },
    });
    expect(glpiScreen('problems')).toEqual({
      kind: 'resource',
      resource: 'problems',
    });
    expect(glpiScreen('mine').filters).toEqual({ mine: true });
  });
  it('explains unsupported and denied operations without treating profile permission as homologation', () => {
    expect(operationBlock({ supported: false })).toBe('unsupported');
    expect(operationBlock({ supported: true, permitted: false })).toBe(
      'jrc_denied'
    );
    expect(
      operationBlock({
        supported: true,
        permitted: true,
        source_allowed: false,
      })
    ).toBe('source_denied');
    expect(
      operationBlock({
        supported: true,
        permitted: true,
        source_allowed: null,
        homologated: false,
      })
    ).toBeNull();
  });
  it('sends only entered descriptor fields and preserves zero for the root entity', () => {
    const descriptor = { fields: ['name', 'is_private', 'entities_id'] };
    expect(
      operationAttributes(descriptor, {
        name: 'Title',
        is_private: 0,
        entities_id: 0,
        hidden: 'bad',
      })
    ).toEqual({ name: 'Title', is_private: 0, entities_id: 0 });
    expect(
      operationAttributes(descriptor, { name: '', entities_id: '' })
    ).toEqual({});
  });
  it('maps relation families explicitly', () => {
    expect(operationFamily('validations')).toBe('validation');
    expect(operationFamily('actor_groups')).toBe('group');
    expect(operationFamily('problems')).toBe('problem');
  });
});
