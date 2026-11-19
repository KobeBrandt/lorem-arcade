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
  /// empty.
  Placement? place(int socket, Gear gear) {
    if (!isEmpty(socket)) return null;
    if (gear.isNumber) {
      for (final n in neighbors(socket)) {
        if (_gears[n] == gear) {
          _gears[n] = Gear.number(gear.value * 2);
          return Placement(n, merged: true);
        }
      }
    }
    _gears[socket] = gear;
    return Placement(socket);
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

/// Numbers for one level. Everything grows with the level number.
class CogLevel {
  CogLevel._({
    required this.level,
    required this.coins,
    required this.waveHp,
    required this.enemyCount,
    required this.enemySpeed,
    required this.enemyDps,
    required this.weapons,
    required this.maxNumber,
    required this.multiplierChance,
    required this.hintSocket,
  });

  /// Level [level] (1-based) on a 5 x 4 board.
  factory CogLevel.forLevel(int level) {
    final l = max(1, level);
    // Difficulty stops growing after level 20.
    final n = min(l, 20) - 1;
    // Weapon A sits on the left edge, weapon B on the right edge.
    const weaponA = 1 * cols + 0;
    const weaponB = 2 * cols + (cols - 1);
    return CogLevel._(
      level: l,
      coins: 8 + 2 * n,
      waveHp: 20 + 14 * n + 3 * n * n,
      enemyCount: min(8, 3 + l ~/ 2),
      enemySpeed: 7 + 0.6 * n,
      enemyDps: 8 + n.toDouble(),
      weapons: l >= 4 ? const [weaponA, weaponB] : const [weaponA],
      maxNumber: min(8, 3 + n ~/ 2),
      multiplierChance: l < 3 ? 0 : min(0.25, 0.12 + 0.02 * n),
      hintSocket: l == 1 ? weaponA + 1 : null,
    );
  }

  static const int cols = 5;
  static const int rows = 4;

  final int level;

  /// Coins to spend in the build phase.
  final int coins;

  /// Shared HP of the whole wave.
  final int waveHp;
  final int enemyCount;

  /// Arena units per second (the arena is [CogBattle.arenaLength] long).
  final double enemySpeed;

  /// Damage per second the front enemy deals while it touches the fighter.
  final double enemyDps;

  /// Weapon sockets on the board edges.
  final List<int> weapons;

  /// Biggest number gear the shop offers.
  final int maxNumber;

  /// Chance that a shop offer is a multiplier gear.
  final double multiplierChance;

  /// Socket highlighted to teach the first placement, or null.
  final int? hintSocket;

  CogBoard newBoard() => CogBoard(cols: cols, rows: rows, weapons: weapons);
}

/// The coins and the three offers of the build phase.
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
