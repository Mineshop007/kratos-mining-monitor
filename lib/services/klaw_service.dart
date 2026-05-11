import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// KlawService — KLAW the honey badger, your mining best friend.
/// Each screen gets its own pool of messages. Zero bleed between screens.
/// Messages must feel personal, funny, useful — not like a UI label.
class KlawService extends ChangeNotifier {
  KlawService._();
  static final instance = KlawService._();

  final _rand = math.Random();

  bool isVisible = false;
  String currentMessage = '';
  int position = 0;

  KlawScreenContext _screen = KlawScreenContext.miners;
  int _lastPosition = -1;
  Timer? _autoTimer;
  Timer? _hideTimer;
  bool _busy = false;

  // ─────────────────────────────────────────────────────────────────────────
  // MESSAGE POOLS — every line must pass the "would a real friend send this?" test
  // ─────────────────────────────────────────────────────────────────────────

  static const _miners = [
    // observational humor
    "you've refreshed this\n3 times in the last minute.\nklaw counted. 👀",
    "a watched miner\nnever finds a block.\nbut we watch anyway 🦡",
    "your electricity bill\nis basically a\nmining subscription 💸",
    "fun fact: you check\nthis app more than\nyour text messages 📱",
    "klaw's been watching\nyour fleet all day.\nyou're welcome. 🦡",
    "that miner in the corner?\nit's been online longer\nthan some marriages 💍",
    // motivational but real
    "every hash is a\nlottery ticket.\nyou have a LOT of tickets 🎰",
    "difficulty is just\nthe universe testing\nhow serious you are ⚡",
    "a solo block hit\non a Tuesday at 3am.\nstay ready. 🌙",
    "your miners don't\ntake breaks.\nnether does klaw. 🦡",
    // useful tips
    "long press any miner\nto quick-delete.\nklaw thinks you knew this. 💡",
    "pull down to refresh\nthe whole fleet at once ↓\nyou're welcome.",
    "tap a miner to see\nits temperature.\nsometimes scary. 🌡️",
    "grid view fits more\nminers on screen.\nif you have many. do you? 👀",
    // personality
    "klaw has no feelings.\nbut if he did,\nhe'd be proud of this fleet 🦡",
    "the number you want\nto see: all green.\nthe number you fear: 0.0 GH/s 💀",
    "somewhere right now\nsomeone just found\na solo block. not you. yet. 🎯",
    "this is fine. 🐕🔥\n(it is actually fine.\nyour fleet is fine.)",
  ];

  static const _minersAllOnline = [
    "FULL FLEET ONLINE 🟢\nevery single one.\nklaw is emotional rn 🦡",
    "all green.\nno excuses.\ntime to find that block. 🎯",
    "this is the part\nwhere you casually\nexpect to find a block 👀",
    "klaw did roll call.\neveryone present.\nlet's get to work. 💪",
    "beautiful. absolutely\nbeautiful.\ndon't touch anything. 🤞",
  ];

  static const _minersOffline = [
    "one of your miners\njust ghosted you.\ncheck the cable first. 🔌",
    "miner offline.\nklaw's first question:\nwhen did you last reboot it? 🔄",
    "is it plugged in?\nklaw has to ask.\nit's always the plug. 😂",
    "offline miner =\nhashes per second: 0.\nthis is a cry for help. 🆘",
    "that miner needs you.\nit's not angry.\njust needs attention. 🥺",
  ];

  static const _minerDetail = [
    "this little machine\nhas been grinding for you\n24/7. respect it. 🙏",
    "temperature check:\nif your hand would melt\non it, that's too hot. 🌡️",
    "best share number?\nthat's the closest\nyou've been to a block. 👀",
    "uptime like that\nmeans you set it up right\nand walked away. smart. 😎",
    "klaw tip: don't restart\na miner that's working fine.\nsuperstition? maybe. 🤞",
    "this miner is hashing\nright now as you read this.\npoetic, really. ⛏️",
    "pool connection solid.\nhashrate stable.\nthis is as good as it gets. 🟢",
    "the efficiency on this one\nis better than\nklaw's patience. 📊",
    "solo mining is\nrunning this miner\nuntil it prints a block 🎰",
    "if this miner\nfinds a block\nklaw will personally celebrate 🦡🎉",
  ];

  static const _settings = [
    "push notifications off?\nbold choice.\nhow will you know when\na miner dies at 3am? 🔔",
    "klaw tip:\nremote access + relay mode =\nyour miners are always reachable 🌍",
    "pool presets:\nset your wallet once.\napply to 10 miners in one tap. ⚡\nyou're welcome.",
    "energy report is hiding\nsomewhere in here.\nyour electricity bill\nwill thank you for finding it 💸",
    "name your miners\nsomething personal.\nNerdQaxe-Kitchen is\na valid miner name 🏠",
    "dark mode only.\nklaw literally cannot\nfunction in light mode 🖤",
    "klaw's favourite setting:\nnone. klaw doesn't\nhave favourite settings.\nbut if he did: alerts. 🔔",
    "did you know:\nyou can schedule your miners\nto restart automatically?\ncheck the FAQ. 📋",
    "tip: set up a pool preset\nfor Mineshop Solo Pool.\nit's where klaw mines. 🦡",
    "the fact that you're\nin settings right now\nmeans you care.\nklaw respects that. 🤝",
    "hardware wallet:\nstay safe out there.\nyour mining profits\nneed somewhere secure 🔐",
    "klaw is watching\nthe settings page\nso you don't\nbreak anything 😅",
  ];

  static const _pools = [
    "solo pool math:\n3.125 BTC ÷ 1 winner = you.\nno split. no fees.\nklaw does not share. 🤑",
    "fun fact: solo miners\nhave found blocks with\nhardware smaller than yours.\njust saying. 💪",
    "pool fees sound small.\n2% of every reward\nevery single block\nfor years. think about it. 💸",
    "stratum URL:\nthe address your miner\ncalls home every few seconds.\nmake it count. 📡",
    "mineshop solo pool:\nklaw's personal choice.\nyour block. your sats.\nzero drama. 🦡",
    "apply your wallet\nto all miners at once.\nthen go do something\nelse for a while ⚡",
    "public pools:\nshared reward, shared luck.\nsolo: YOUR luck.\nklaw prefers his own luck. 🎰",
    "reminder:\nalways double-check\nyour BTC address.\nthere is no ctrl+z\nin bitcoin. 😬",
    "a miner pointing\nat the wrong pool\nis a miner pointing\nat nothing. fix it. 🎯",
    "klaw switched to solo\nand never looked back.\npool fees are a tax\non impatient people. 💎",
  ];

  static const _hallOfFame = [
    "these people found\nactual bitcoin blocks.\nwith home hardware.\nit's not a myth. 🏆",
    "3.125 BTC.\nfound by someone\nat home.\nwith a miner like yours. 👀",
    "the biggest lie\nin bitcoin:\n'home miners can't\nfind blocks' 💀",
    "study this list.\nsame miners as you.\nsame pools as you.\ndifferent result. yet. 🔥",
    "klaw knows\nsome of these people.\nthey're not special.\nthey were just still online. ⛏️",
    "block reward: 3.125 BTC.\ncurrent price: do the math.\nyour miner: already hashing. 🤑",
    "someone found a block\nat 2:47am on a Thursday.\nthe network doesn't\ncare about your schedule. 🌙",
    "your name could\nbe on this list.\nthe only requirement:\nstill be running when it hits 🎯",
    "hall of fame entry:\nblock found. life changed.\nit takes one lucky hash.\nyou have millions daily. 🎰",
  ];

  static const _dashboard = [
    "dashboard overview:\nthe number you want\nto go up: hashrate.\nthe other one: earnings 📊",
    "your daily earnings\nare small now.\nbut you're mining bitcoin.\nthat ages well. 💎",
    "klaw checks this\ndashboard too.\nlooks good today.\ndon't ask about yesterday 😅",
    "fleet uptime is\nthe metric nobody\ntalks about enough.\nconsistency beats luck 📅",
    "best share here\nis your personal record.\nhow close have you been?\npretty close. 👀",
    "every satoshi earned\nfrom mining is a satoshi\nyou didn't have to buy. 💡",
    "this dashboard is\nklaw's second home.\ndon't redecorate. 🦡",
    "total hashrate × time =\nyour chance at a block.\nboth numbers matter.\nklaw runs the math. 🧮",
  ];

  static const _addMiner = [
    "new miner incoming! 🦡\nklaw is making room\nin the fleet manifest.",
    "name it well.\nyour miner will have\nthis name forever.\nor until you delete it. 🏷️",
    "adding a miner:\nstep one: enter IP.\nstep two: watch the hashes.\nstep three: check obsessively. 📱",
    "every great fleet\nstarted with one miner.\nyou're building something here. 🏗️",
    "klaw welcomes\nall new recruits.\nmay your uptime be\nlonger than your patience ⛏️",
    "pro tip: give it a name\nthat tells you where it is.\nbedroom, garage, attic,\nyou'll thank yourself. 🗺️",
  ];

  static const _circuit = [
    "circuit mode:\nyou're thinking about\npower consumption.\nthat means you're serious. ⚡",
    "klaw tip:\nnever run your breaker\nabove 80% load.\nthe other 20% is for peace of mind 🔌",
    "remote access:\ncontrol your miners\nfrom a different country.\nklaw has done this. 🌍",
    "your electricity cost\nis the only variable\nyou can actually control.\ncircuit view helps. 💸",
    "relay mode + circuit view\n= full remote mining control.\nyou basically have a\nmining data center now. 🏭",
  ];

  // ── Dynamic celebration messages ─────────────────────────────────────────

  static String bestShareMsg(String diff) =>
      '🎉 $diff DIFFICULTY SHARE!\nthat was genuinely close\nto a block. klaw noticed. 👀';

  static String newRecordMsg(String diff) =>
      '👑 PERSONAL BEST: $diff diff!\nif blocks were music\nthat would be top 10 🔥';

  static String offlineMsg(int count) =>
      '$count miner${count > 1 ? 's' : ''} just went offline.\nklaw is NOT happy.\ncheck the fleet 🔌';

  static String backOnlineMsg(String name) =>
      '$name is back!\nklaw was pacing.\ndon\'t do that again. 🦡';

  static String allOnlineMsg() =>
      'every miner just\ncame back online.\nklaw breathed again. 🟢🦡';

  // ── API ──────────────────────────────────────────────────────────────────

  void startAuto() {
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(seconds: 30), () {
      _autoFire();
      _autoTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _autoFire(),
      );
    });
  }

  void stopAuto() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  void setScreen(KlawScreenContext ctx) {
    if (_screen == ctx) return;
    _screen = ctx;
    _hideTimer?.cancel();
    isVisible = false;
    _busy = false;
    // Fire a fresh contextual message 5s after screen change
    Timer(const Duration(milliseconds: 5000), () {
      if (_screen == ctx) _autoFire();
    });
  }

  void trigger(String message, {int? atPosition}) =>
      _show(message, atPosition: atPosition);

  void dismiss() {
    if (!isVisible) return;
    isVisible = false;
    _busy = false;
    _hideTimer?.cancel();
    notifyListeners();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  void _autoFire() {
    if (_busy) return;
    _show(_pickMessage());
  }

  void _show(String message, {int? atPosition}) {
    _hideTimer?.cancel();
    final positions = [0, 1, 2, 3];
    positions.remove(_lastPosition);
    final pos = atPosition ?? positions[_rand.nextInt(positions.length)];
    _lastPosition = pos;
    isVisible = true;
    _busy = true;
    currentMessage = message;
    position = pos;
    notifyListeners();
    _hideTimer = Timer(const Duration(milliseconds: 5800), () {
      isVisible = false;
      _busy = false;
      notifyListeners();
    });
  }

  String _pickMessage() {
    switch (_screen) {
      case KlawScreenContext.miners:
        return _pick(_miners);
      case KlawScreenContext.minersAllOnline:
        return _pick(_minersAllOnline);
      case KlawScreenContext.minersOffline:
        return _pick(_minersOffline);
      case KlawScreenContext.minerDetail:
        return _pick(_minerDetail);
      case KlawScreenContext.settings:
        return _pick(_settings);
      case KlawScreenContext.pools:
        return _pick(_pools);
      case KlawScreenContext.hallOfFame:
        return _pick(_hallOfFame);
      case KlawScreenContext.dashboard:
        return _pick(_dashboard);
      case KlawScreenContext.addMiner:
        return _pick(_addMiner);
      case KlawScreenContext.circuit:
        return _pick(_circuit);
    }
  }

  String _pick(List<String> list) => list[_rand.nextInt(list.length)];

  @override
  void dispose() {
    _autoTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }
}

enum KlawScreenContext {
  miners,
  minersAllOnline,
  minersOffline,
  minerDetail,
  settings,
  pools,
  hallOfFame,
  dashboard,
  addMiner,
  circuit,
}
