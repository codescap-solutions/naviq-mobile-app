import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isDeletionRestricted (server isallowdelete -> toggle)', () {
    test('isallowdelete false means restricted', () {
      expect(HomeRepository.isDeletionRestricted({'isallowdelete': false}), isTrue);
    });

    test('isallowdelete true means not restricted', () {
      expect(HomeRepository.isDeletionRestricted({'isallowdelete': true}), isFalse);
    });

    test('missing key, null, and non-map payloads are not restricted', () {
      expect(HomeRepository.isDeletionRestricted({}), isFalse);
      expect(HomeRepository.isDeletionRestricted({'isallowdelete': null}), isFalse);
      expect(HomeRepository.isDeletionRestricted(null), isFalse);
      expect(HomeRepository.isDeletionRestricted('oops'), isFalse);
    });

    test('a non-bool value is ignored rather than coerced', () {
      expect(HomeRepository.isDeletionRestricted({'isallowdelete': 'false'}), isFalse);
      expect(HomeRepository.isDeletionRestricted({'isallowdelete': 0}), isFalse);
    });

    test('toggle round trip: the app sends isallowdelete = !enabled', () {
      // Parent turns "Restrict from Deleting" ON -> sends isallowdelete:false
      // -> server stores false -> GET returns false -> toggle reads ON again.
      for (final enabled in [true, false]) {
        final sent = !enabled;
        expect(HomeRepository.isDeletionRestricted({'isallowdelete': sent}), enabled);
      }
    });
  });
}
