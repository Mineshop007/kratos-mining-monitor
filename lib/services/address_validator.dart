import '../models/coin.dart';
import '../models/pool_preset.dart';

class AddressValidation {
  final bool ok;
  final String message;

  const AddressValidation.ok()
      : ok = true,
        message = '';

  const AddressValidation.warn(this.message) : ok = false;
}

class AddressValidator {
  static AddressValidation validateForPool({
    required Coin coin,
    required WorkerFormat format,
    required String worker,
  }) {
    final value = worker.trim();
    if (value.isEmpty) {
      return const AddressValidation.warn(
          'Enter a wallet address or pool account first.');
    }
    if (format == WorkerFormat.account ||
        format == WorkerFormat.accountWorker ||
        coin == Coin.sha256Auto) {
      if (value.length < 3) {
        return const AddressValidation.warn('Pool account looks too short.');
      }
      return const AddressValidation.ok();
    }
    if (coin == Coin.bch ||
        format == WorkerFormat.bchAddress ||
        format == WorkerFormat.bchAddressWorker) {
      return _bch(value);
    }
    if (coin == Coin.btc ||
        format == WorkerFormat.btcAddress ||
        format == WorkerFormat.btcAddressWorker) {
      return _btc(value);
    }
    return const AddressValidation.ok();
  }

  static AddressValidation _btc(String value) {
    final base = value.split('.').first;
    final lower = base.toLowerCase();
    final ok =
        lower.startsWith('bc1') || base.startsWith('1') || base.startsWith('3');
    if (!ok) {
      return const AddressValidation.warn(
        'This does not look like a BTC address. You can still use pool usernames.',
      );
    }
    return const AddressValidation.ok();
  }

  static AddressValidation _bch(String value) {
    final base = value.split('.').first;
    final lower = base.toLowerCase();
    final ok = lower.startsWith('bitcoincash:') ||
        lower.startsWith('q') ||
        lower.startsWith('p') ||
        base.startsWith('1') ||
        base.startsWith('3');
    if (!ok) {
      return const AddressValidation.warn(
        'This does not look like a BCH address. Use CashAddr or your pool account.',
      );
    }
    return const AddressValidation.ok();
  }
}
