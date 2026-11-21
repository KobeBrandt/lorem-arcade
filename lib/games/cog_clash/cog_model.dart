import 'dart:math';

/// What a gear on the board does.
enum GearKind { number, multiplier }

/// One gear the player can buy and place.
class Gear {
  const Gear.number(this.value) : kind = GearKind.number;
  const Gear.multiplier(this.value) : kind = GearKind.multiplier;

  final GearKind kind;

  /// Points added (number gear) or the factor (multiplier gear).
  final int value;

  bool get isNumber => kind == GearKind.number;

  /// Text drawn on the gear, for example '+3' or '2x'.
  String get label => isNumber ? '+$value' : '${value}x';

  /// Coin price in the shop: a number gear costs its value, a 2x gear
  /// costs 6 and a 3x gear costs 10.
  int get price => isNumber ? value : (value == 2 ? 6 : 10);

  /// Coins back when the gear is sold: half its price, rounded down.
  /// A merged number gear sells by its value.
  int get sellPrice => price ~/ 2;

  @override
  bool operator ==(Object other) =>
      other is Gear && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => label;
}

/// Where a placed gear ended up.
class Placement {
  const Placement(this.socket, {this.merged = false});

  /// Socket that holds the new (or merged) gear.
  final int socket;

  /// True when the gear merged into an equal neighbor.
  final bool merged;
}

/// Grid of gear sockets with fixed weapon gears on the edges.
/// Sockets are numbered row by row: `row * cols + col`.
class CogBoard {
  CogBoard({this.cols = 5, this.rows = 4, required List<int> weapons})
    : weapons = List.unmodifiable(weapons),
      _gears = List.filled(cols * rows, null);

  CogBoard._copy(CogBoard other)
    : cols = other.cols,
      rows = other.rows,
      weapons = other.weapons,
      _gears = List.of(other._gears);

  final int cols;
  final int rows;

  /// Sockets that hold a weapon gear.
  final List<int> weapons;

  final List<Gear?> _gears;

  int get socketCount => cols * rows;

  int socket(int col, int row) => row * cols + col;

  int colOf(int socket) => socket % cols;

  int rowOf(int socket) => socket ~/ cols;

  Gear? gearAt(int socket) => _gears[socket];

  bool isWeapon(int socket) => weapons.contains(socket);

  /// True when the socket has no gear and no weapon.
  bool isEmpty(int socket) => !isWeapon(socket) && _gears[socket] == null;

  bool get hasGears => _gears.any((g) => g != null);

  /// Orthogonal neighbors in the order left, right, up, down.
  List<int> neighbors(int socket) {
    final c = colOf(socket);
    final r = rowOf(socket);
    return [
      if (c > 0) socket - 1,
      if (c < cols - 1) socket + 1,
      if (r > 0) socket - cols,
      if (r < rows - 1) socket + cols,
    ];
  }

  /// Puts [gear] in an empty [socket]. Returns null when the socket is
  /// taken. A number gear next to a number gear of the same value merges
  /// into that neighbor (which then holds the sum) and [socket] stays
  /// empty. The merged gear keeps merging while it has an equal number
  /// neighbor, so 2 + 2 next to a 4 ends as one 8.
  Placement? place(int socket, Gear gear) {
    if (!isEmpty(socket)) return null;
    if (!gear.isNumber) {
      _gears[socket] = gear;
      return Placement(socket);
    }
    var at = socket;
    var current = gear;
    var merged = false;
    while (true) {
      final into = _equalNeighbor(at, current);
      if (into == null) break;
      _gears[at] = null;
      current = Gear.number(current.value * 2);
      _gears[into] = current;
      at = into;
      merged = true;
    }
    _gears[at] = current;
    return Placement(at, merged: merged);
  }

  /// First neighbor of [socket] that holds a gear equal to [gear].
  int? _equalNeighbor(int socket, Gear gear) {
    for (final n in neighbors(socket)) {
      if (_gears[n] == gear) return n;
    }
    return null;
  }

  /// Takes the gear out of [socket] and returns it. Null when the socket
  /// holds no gear (weapons cannot be removed).
  Gear? remove(int socket) {
    if (isWeapon(socket)) return null;
    final gear = _gears[socket];
    _gears[socket] = null;
    return gear;
  }

  /// Gear sockets linked to [weapon] through orthogonally adjacent gears.
  Set<int> chainOf(int weapon) {
    final seen = <int>{};
    final queue = [weapon];
    while (queue.isNotEmpty) {
      final s = queue.removeLast();
      for (final n in neighbors(s)) {
        if (_gears[n] != null && seen.add(n)) queue.add(n);
      }
    }
    return seen;
  }

  /// Gear sockets that turn (linked to any weapon).
  Set<int> get powered => {for (final w in weapons) ...chainOf(w)};

  /// Weapon power: the sum of the linked number gears times the product
  /// of the linked multipliers. 0 without a linked number gear.
  int powerOf(int weapon) {
    var sum = 0;
    var factor = 1;
    for (final s in chainOf(weapon)) {
      final g = _gears[s]!;
      if (g.isNumber) {
        sum += g.value;
      } else {
        factor *= g.value;
      }
    }
    return sum * factor;
  }

  /// Power of each weapon, in the order of [weapons].
  List<int> get powers => [for (final w in weapons) powerOf(w)];

  int get totalPower => powers.fold(0, (a, b) => a + b);

  /// Empty sockets that would be linked to a weapon right away.
  Set<int> get linkedEmptySockets {
    final sources = {...weapons, ...powered};
    return {
      for (final s in sources)
        for (final n in neighbors(s))
          if (isEmpty(n)) n,
    };
  }

  CogBoard copy() => CogBoard._copy(this);
}

/// One wave of enemies. They share [hp]; each defeated enemy pays
/// [coinsPerKill] coins.
class CogWave {
  const CogWave({
    required this.hp,
    required this.enemyCount,
    required this.speed,
    required this.dps,
    required this.coinsPerKill,
  });

  /// Shared HP of the whole wave.
  final int hp;
  final int enemyCount;

  /// Arena units per second (the arena is [CogBattle.arenaLength] long).
  final double speed;

  /// Damage per second the front enemy deals while it touches the fighter.
  final double dps;

  final int coinsPerKill;

  /// Wave with strength [s]: 0 is the first wave of level 1, and every
  /// step up is a little harder.
  factory CogWave.ofStrength(double s, int enemyCount) {
    final capped = min(s, 24.0);
    return CogWave(
      hp: (24 * pow(1.32, s) + 6 * s).round(),
      enemyCount: enemyCount,
      speed: 6 + 0.45 * capped,
      dps: 8 + 0.7 * capped,
      coinsPerKill: 1 + (s ~/ 4),
    );
  }
}

/// Numbers for one level, or for the endless run. Enemies come in waves
/// while the player builds; everything grows with the level number and
/// with each wave.
class CogLevel {
  CogLevel._({
    required this.level,
    required this.coins,
    required this.waveCount,
    required this.weapons,
    required this.maxNumber,
    required this.multiplierChance,
    required this.hintSocket,
    required this.strength,
    required this.strengthPerWave,
    required this.enemyCount,
  });

  /// Level [level] (1-based) on a 5 x 4 board.
  factory CogLevel.forLevel(int level) {
    final l = max(1, level);
    // Difficulty stops growing after level 20.
    final n = min(l, 20) - 1;
    return CogLevel._(
      level: l,
      coins: 6 + n,
      waveCount: l <= 3
          ? 2
          : l <= 9
          ? 3
          : 4,
      weapons: l >= 4 ? const [weaponA, weaponB] : const [weaponA],
      maxNumber: min(8, 3 + n ~/ 2),
      multiplierChance: l < 3 ? 0 : min(0.25, 0.12 + 0.02 * n),
      hintSocket: l == 1 ? weaponA + 1 : null,
      strength: n * 0.8,
      strengthPerWave: 1.5,
      enemyCount: min(6, 3 + l ~/ 3),
    );
  }

  /// The endless run: waves never stop and keep getting stronger.
  factory CogLevel.endless() => CogLevel._(
    level: 0,
    coins: 8,
    waveCount: null,
    weapons: const [weaponA, weaponB],
    maxNumber: 6,
    multiplierChance: 0.2,
    hintSocket: null,
    strength: 0,
    strengthPerWave: 1.2,
    enemyCount: 4,
  );

  static const int cols = 5;
  static const int rows = 4;

  /// Weapon A sits on the left edge, weapon B on the right edge.
  static const int weaponA = 1 * cols + 0;
  static const int weaponB = 2 * cols + (cols - 1);

  /// 1-based level, 0 for the endless run.
  final int level;

  /// Coins at the start. Defeated enemies pay more.
  final int coins;

  /// Waves to defeat to win, or null for the endless run.
  final int? waveCount;

  /// Weapon sockets on the board edges.
  final List<int> weapons;

  /// Biggest number gear the shop offers.
  final int maxNumber;

  /// Chance that a shop offer is a multiplier gear.
  final double multiplierChance;

  /// Socket highlighted to teach the first placement, or null.
  final int? hintSocket;

  /// Strength of the first wave, see [CogWave.ofStrength].
  final double strength;

  /// Strength added by each later wave.
  final double strengthPerWave;

  /// Enemies per wave (the endless run adds more over time).
  final int enemyCount;

  bool get isEndless => waveCount == null;

  /// Wave [index] (0-based).
  CogWave wave(int index) => CogWave.ofStrength(
    strength + strengthPerWave * index,
    isEndless ? min(8, enemyCount + index ~/ 3) : enemyCount,
  );

  CogBoard newBoard() => CogBoard(cols: cols, rows: rows, weapons: weapons);
}

/// The coins and the three offers of the shop.
class CogShop {
  CogShop(this.config) : coins = config.coins, _random = Random(config.level) {
    for (var i = 0; i < offerCount; i++) {
      offers.add(_roll());
    }
  }

  static const int offerCount = 3;
  static const int rerollPrice = 1;

  final CogLevel config;
  final Random _random;
  int coins;
  final List<Gear> offers = [];

  bool canAfford(int offer) => offers[offer].price <= coins;

  /// Pays for offer [offer] and puts a new offer in its place.
  /// Returns null when there are not enough coins.
  Gear? buy(int offer) {
    if (!canAfford(offer)) return null;
    final gear = offers[offer];
    coins -= gear.price;
    offers[offer] = _roll();
    return gear;
  }

  /// Adds the sell price of [gear] to the coins.
  void sell(Gear gear) => coins += gear.sellPrice;

  /// Replaces all offers for [rerollPrice]. False without coins.
  bool reroll() {
    if (coins < rerollPrice) return false;
    coins -= rerollPrice;
    for (var i = 0; i < offerCount; i++) {
      offers[i] = _roll();
    }
    return true;
  }

  Gear _roll() {
    if (_random.nextDouble() < config.multiplierChance) {
      return Gear.multiplier(_random.nextDouble() < 0.7 ? 2 : 3);
    }
    return Gear.number(1 + _random.nextInt(config.maxNumber));
  }
}

/// Stars by the fighter HP left: 3 above 2/3, 2 above 1/3, else 1.
int starsForHp(double hp, double maxHp) {
  final f = hp / maxHp;
  if (f > 2 / 3) return 3;
  if (f > 1 / 3) return 2;
  return 1;
}
