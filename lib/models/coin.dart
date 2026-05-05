import 'package:flutter/material.dart';
import '../theme/volt_theme.dart';

/// Mining algorithms supported by Kratos v1.2.0.
enum MiningAlgo {
  sha256,        // BTC, BCH
  scrypt,        // LTC, DOGE (merge mined)
  kheavyhash,    // KAS
  blake3,        // ALPH
  eaglesong,     // CKB
  etcChash,      // ETC
  unknown,
}

extension MiningAlgoExt on MiningAlgo {
  String get displayName => switch (this) {
    MiningAlgo.sha256     => 'SHA-256',
    MiningAlgo.scrypt     => 'Scrypt',
    MiningAlgo.kheavyhash => 'KHeavyHash',
    MiningAlgo.blake3     => 'Blake3',
    MiningAlgo.eaglesong  => 'Eaglesong',
    MiningAlgo.etcChash   => 'EtcHash',
    MiningAlgo.unknown    => 'Unknown',
  };
}

/// Coins surfaced as first-class in 1.2.0. Anything else falls back to BTC
/// rendering so we never invent values.
enum Coin {
  btc,
  ltc,    // also tracks merged DOGE
  doge,
  kas,
  alph,
  ckb,
  etc,
  unknown,
}

extension CoinExt on Coin {
  String get ticker => switch (this) {
    Coin.btc     => 'BTC',
    Coin.ltc     => 'LTC',
    Coin.doge    => 'DOGE',
    Coin.kas     => 'KAS',
    Coin.alph    => 'ALPH',
    Coin.ckb     => 'CKB',
    Coin.etc     => 'ETC',
    Coin.unknown => '—',
  };

  String get displayName => switch (this) {
    Coin.btc     => 'Bitcoin',
    Coin.ltc     => 'Litecoin',
    Coin.doge    => 'Dogecoin',
    Coin.kas     => 'Kaspa',
    Coin.alph    => 'Alephium',
    Coin.ckb     => 'Nervos CKB',
    Coin.etc     => 'Ethereum Classic',
    Coin.unknown => 'Unknown',
  };

  /// CoinGecko ID for price lookups. Stable strings, never invented.
  String? get coinGeckoId => switch (this) {
    Coin.btc     => 'bitcoin',
    Coin.ltc     => 'litecoin',
    Coin.doge    => 'dogecoin',
    Coin.kas     => 'kaspa',
    Coin.alph    => 'alephium',
    Coin.ckb     => 'nervos',
    Coin.etc     => 'ethereum-classic',
    Coin.unknown => null,
  };

  Color get color => switch (this) {
    Coin.btc     => KratosColors.coinBtc,
    Coin.ltc     => KratosColors.coinLtc,
    Coin.doge    => KratosColors.coinDoge,
    Coin.kas     => KratosColors.coinKas,
    Coin.alph    => KratosColors.coinAlph,
    Coin.ckb     => KratosColors.coinCkb,
    Coin.etc     => KratosColors.muted,
    Coin.unknown => KratosColors.muted,
  };
}

class CoinAlgoMapping {
  /// Canonical (algo, coin) tuple for a given device family.
  /// Does not invent — when unknown, returns (unknown, unknown).
  static (MiningAlgo, Coin) forMinerType(String typeName) {
    final t = typeName.toLowerCase();
    // Bitcoin SHA-256 ASICs (BitAxe family, NerdAxe, Avalon, Antminer S/T,
    // Whatsminer M, Lucky Miner)
    const sha256Names = {
      'bitaxegamma', 'bitaxeultra', 'bitaxegt',
      'nerdqaxe', 'nerdoctaxe',
      'avalonnano3', 'avalonnano3s', 'avalonmini3', 'avalonq',
      'antminer', 'whatsminer',
      'goldshell', 'generic',
    };
    if (sha256Names.contains(t)) {
      return (MiningAlgo.sha256, Coin.btc);
    }
    return (MiningAlgo.unknown, Coin.unknown);
  }
}
