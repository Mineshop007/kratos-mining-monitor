import '../models/coin.dart';
import '../models/miner.dart';
import 'avalon_api.dart';
import 'cgminer_api.dart';
import 'esp_miner_api.dart';
import 'pool_catalog_service.dart';
import 'relay_service.dart';

class PoolApplyResult {
  final Miner miner;
  final bool success;
  final String message;

  const PoolApplyResult({
    required this.miner,
    required this.success,
    required this.message,
  });
}

class PoolApplyService {
  static Future<PoolApplyResult> applyCatalogPool({
    required Miner miner,
    required PoolCatalogEntry pool,
    required String worker,
    String? fallbackWorker,
  }) async {
    final user = worker.trim().isEmpty ? 'worker' : worker.trim();
    final pass = pool.password.isEmpty ? 'x' : pool.password;
    var ok = false;

    try {
      if (miner.type.apiType == ApiType.espMinerHttp) {
        ok = await EspMinerAPI.instance.setPool(
          miner.ip,
          miner.port,
          stratumUrl: pool.host,
          stratumPort: pool.port,
          stratumUser: user,
          stratumPass: pass,
          remoteUrl: miner.remoteUrl,
          isRemote: miner.isRemote,
        );
        if (!ok && _relayAvailable(miner)) {
          ok = await EspMinerAPI.instance.setPool(
            miner.ip,
            miner.port,
            stratumUrl: pool.host,
            stratumPort: pool.port,
            stratumUser: user,
            stratumPass: pass,
            isRemote: true,
          );
        }
      } else if (miner.type.apiType == ApiType.avalonHttp) {
        ok = await AvalonAPI.instance.setPool(
          miner.ip,
          miner.port,
          host: pool.host,
          poolPort: pool.port,
          user: user,
          remoteUrl: miner.remoteUrl,
          isRemote: miner.isRemote,
        );
        if (!ok && _relayAvailable(miner)) {
          ok = await AvalonAPI.instance.setPool(
            miner.ip,
            miner.port,
            host: pool.host,
            poolPort: pool.port,
            user: user,
            isRemote: true,
          );
        }
      } else {
        final url = pool.stratumUrl;
        if (miner.type == MinerType.avalonQ ||
            miner.type == MinerType.avalonMini3) {
          ok = await CGMinerAPI.instance.setPoolAscset(
            miner.ip,
            miner.port,
            primaryUrl: url,
            primaryUser: user,
            primaryPass: pass,
            rebootAfterSave: true,
            remoteUrl: miner.remoteUrl,
            isRemote: miner.isRemote,
          );
          if (!ok && _relayAvailable(miner)) {
            ok = await CGMinerAPI.instance.setPoolAscset(
              miner.ip,
              miner.port,
              primaryUrl: url,
              primaryUser: user,
              primaryPass: pass,
              rebootAfterSave: true,
              isRemote: true,
            );
          }
        } else {
          ok = await CGMinerAPI.instance.setPools(
            miner.ip,
            miner.port,
            [
              {'url': url, 'user': user, 'pass': pass}
            ],
            remoteUrl: miner.remoteUrl,
            isRemote: miner.isRemote,
          );
          if (!ok && _relayAvailable(miner)) {
            ok = await CGMinerAPI.instance.setPools(
              miner.ip,
              miner.port,
              [
                {'url': url, 'user': user, 'pass': pass}
              ],
              isRemote: true,
            );
          }
        }
      }

      if (ok) {
        miner.coin = pool.coin == Coin.sha256Auto
            ? PoolCatalogService.inferCoinFromHost(pool.host)
            : pool.coin;
      }
      return PoolApplyResult(
        miner: miner,
        success: ok,
        message: ok ? 'Applied' : 'Miner did not confirm pool change',
      );
    } catch (e) {
      return PoolApplyResult(
        miner: miner,
        success: false,
        message: e.toString(),
      );
    }
  }

  static bool _relayAvailable(Miner miner) =>
      !miner.isRemote &&
      (RelayService.instance.state == RelayState.bridgeOnline ||
          RelayService.instance.state == RelayState.connected);
}
