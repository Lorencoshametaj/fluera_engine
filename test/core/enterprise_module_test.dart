import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_engine/src/core/enterprise/enterprise_module.dart';
import 'package:fluera_engine/src/core/rbac/permission_service.dart';
import 'package:fluera_engine/src/core/modules/canvas_module.dart';

void main() {
  // =========================================================================
  // FeatureFlagService
  // =========================================================================

  group('FeatureFlagService', () {
    late FeatureFlagService service;

    setUp(() => service = FeatureFlagService());

    test('unknown flag returns false', () {
      expect(service.isEnabled('nonexistent'), isFalse);
    });

    test('loadDefaults enables flags', () {
      service.loadDefaults({'feature_a': true, 'feature_b': false});
      expect(service.isEnabled('feature_a'), isTrue);
      expect(service.isEnabled('feature_b'), isFalse);
    });

    test('setOverride overrides defaults', () {
      service.loadDefaults({'feature_a': false});
      service.setOverride('feature_a', true);
      expect(service.isEnabled('feature_a'), isTrue);
    });

    test('removeOverride restores default', () {
      service.loadDefaults({'feature_a': false});
      service.setOverride('feature_a', true);
      service.removeOverride('feature_a');
      expect(service.isEnabled('feature_a'), isFalse);
    });

    test('clearOverrides removes all overrides', () {
      service.setOverride('a', true);
      service.setOverride('b', true);
      service.clearOverrides();
      expect(service.isEnabled('a'), isFalse);
      expect(service.isEnabled('b'), isFalse);
    });

    test('allFlags merges defaults and overrides', () {
      service.loadDefaults({'a': true, 'b': false});
      service.setOverride('b', true);
      service.setOverride('c', true);
      expect(service.allFlags, {'a': true, 'b': true, 'c': true});
    });
  });

  // =========================================================================
  // AnalyticsService
  // =========================================================================

  group('AnalyticsService', () {
    late AnalyticsService service;

    setUp(() => service = AnalyticsService());

    test('trackEvent increments pending count', () {
      service.trackEvent('test_event');
      expect(service.pendingEvents, 1);
    });

    test('trackEvent stores properties', () {
      service.trackEvent('click', {'button': 'save'});
      expect(service.pendingEvents, 1);
    });

    test('flush clears buffer', () {
      service.trackEvent('e1');
      service.trackEvent('e2');
      service.flush();
      expect(service.pendingEvents, 0);
    });

    test('flush sends events to sink', () {
      final received = <AnalyticsEvent>[];
      service.registerSink((events) => received.addAll(events));

      service.trackEvent('e1');
      service.trackEvent('e2');
      service.flush();

      expect(received.length, 2);
      expect(received[0].name, 'e1');
      expect(received[1].name, 'e2');
    });

    test('flush with no events does nothing', () {
      int callCount = 0;
      service.registerSink((_) => callCount++);
      service.flush();
      expect(callCount, 0);
    });

    test('auto-flushes at 100 events', () {
      final received = <AnalyticsEvent>[];
      service.registerSink((events) => received.addAll(events));

      for (int i = 0; i < 100; i++) {
        service.trackEvent('event_$i');
      }
      // Should have auto-flushed
      expect(received.length, 100);
      expect(service.pendingEvents, 0);
    });
  });

  // =========================================================================
  // EnterpriseRBACService
  // =========================================================================

  group('EnterpriseRBACService', () {
    late EnterpriseRBACService rbac;

    setUp(() {
      rbac = EnterpriseRBACService(permissionService: PermissionService());
    });

    test('no permissions by default', () {
      expect(rbac.hasPermission('edit'), isFalse);
      expect(rbac.hasRole('admin'), isFalse);
    });

    test('assignRoles sets active roles', () {
      rbac.assignRoles({'admin', 'editor'});
      expect(rbac.hasRole('admin'), isTrue);
      expect(rbac.hasRole('editor'), isTrue);
      expect(rbac.hasRole('viewer'), isFalse);
    });

    test('defineRole + assignRoles grants permissions', () {
      rbac.defineRole('editor', {'edit', 'view'});
      rbac.assignRoles({'editor'});
      expect(rbac.hasPermission('edit'), isTrue);
      expect(rbac.hasPermission('view'), isTrue);
      expect(rbac.hasPermission('delete'), isFalse);
    });

    test('multiple roles combine permissions', () {
      rbac.defineRole('viewer', {'view'});
      rbac.defineRole('admin', {'edit', 'delete'});
      rbac.assignRoles({'viewer', 'admin'});
      expect(rbac.hasPermission('view'), isTrue);
      expect(rbac.hasPermission('edit'), isTrue);
      expect(rbac.hasPermission('delete'), isTrue);
    });

    test('reassigning roles clears previous', () {
      rbac.defineRole('admin', {'edit', 'delete'});
      rbac.assignRoles({'admin'});
      rbac.assignRoles({}); // clear
      expect(rbac.hasRole('admin'), isFalse);
      expect(rbac.hasPermission('edit'), isFalse);
    });

    test('activeRoles returns unmodifiable set', () {
      rbac.assignRoles({'admin'});
      expect(rbac.activeRoles, {'admin'});
    });
  });

  // =========================================================================
  // EnterpriseModule Lifecycle
  // =========================================================================

  group('EnterpriseModule lifecycle', () {
    test('starts uninitialized', () {
      final module = EnterpriseModule();
      expect(module.isInitialized, isFalse);
      expect(module.moduleId, 'enterprise');
      expect(module.displayName, 'Enterprise');
    });

    test('nodeDescriptors is empty', () {
      expect(EnterpriseModule().nodeDescriptors, isEmpty);
    });

    test('createTools returns empty', () {
      expect(EnterpriseModule().createTools(), isEmpty);
    });
  });
}
