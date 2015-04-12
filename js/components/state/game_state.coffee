root = exports ? this

TRIGGERS = 0
FLOORS = 1
WALLS = 2
CREATURES = 3
NUM_LAYERS = 4

MAX_OUTPUT_LENGTH = 7

RIGHT = { n: 'ne', ne: 'e', e: 'se', se: 's', s: 'sw', sw: 'w', w: 'nw', nw: 'n' }
LEFT = { n: 'nw', ne: 'n', e: 'ne', se: 'e', s: 'se', sw: 's', w: 'sw', nw: 'w' }
REVERSE = { n: 's', ne: 'sw', e: 'w', se: 'nw', s: 'n', sw: 'ne', w: 'e', nw: 'se' }

class GameState
  constructor: (@map_width, @map_height) ->
    @_map = new Map @map_width, @map_height, NUM_LAYERS
    @floor = 0

    @_player_generator = new PlayerGenerator()
    @_monster_generator = new MonsterGenerator()

    @_cave_generator = new MapGenerator @map_width, @map_height

    @clear_map()
    @exit_locked = true
    @_entities = {}

    @output = []
    @actors = {}
    
    @_player_fov_map = {}
    
    @_gold_map = {}
    @_potions_map = {}

  # GENERATORS

  generate_player: (gender, race, klass) ->
    @_player = @_player_generator.generate gender, race, klass
    @player_id = @_player.id

    @_add @_player
    
    @_player

  generate_monster: (rarity) ->
    monster = @_monster_generator.generate rarity, @floor
    @_add monster
    monster
    

  generate_cave: ->
    @clear_map()

    @_cave_generator.run (i, j, layer, type) =>
      @_map.set_tile i, j, layer, type
      
      
  generate_items: ->
    
  
  # CLEARING

  next_floor: ->
    @floor += 1

  clear_map: ->
    @_map.clear()
    @_gold_map = {}
    @_potions_map = {}

  clear_monsters: ->
    @each_monster (id) =>
      @remove id

  clear_output: ->
    @output = []

  # ADDERS AND GETTERS

  add_trigger: (i, j, trigger) ->
    @_map.set_tile i, j, TRIGGERS, trigger

  get_trigger: (i, j) ->
    @_map.get_tile i, j, TRIGGERS

  add_entrance: (i, j) ->
    @_map.set_tile i, j, FLOORS, 'entrance'

  get_entrances: ->
    @_find_spaces (i, j) =>
      @is_entrance i, j

  add_exit: (i, j) ->
    @_map.set_tile i, j, FLOORS, 'exit'
    @exit_locked = true

  get_exits: ->
    @_find_spaces (i, j) =>
      @is_exit i, j

  register_actor: (id, actor) ->
    @actors[id] = actor

  unregister_actor: (id) ->
    delete @actors[id]

  get_actor: (id) ->
    @actors[id]

  # ITERATORS

  each_creature: (fn) ->
    $.each @_entities, (k, e) =>
      fn e.id

  each_monster: (fn) ->
    $.each @_entities, (k, e) =>
      fn e.id unless e.id == @player_id

  each_tile: (fn) ->
    @_map.each fn

  # QUERIES

  exists: (id) -> !!@_entities[id]
  get_pos: (id) -> @_entities[id].pos()
  get_attack: (id) -> @_entities[id].attack
  get_hp: (id) -> @_entities[id].hp
  get_max_hp: (id) -> @_entities[id].max_hp
  get_mp: (id) -> @_entities[id].mp
  get_max_mp: (id) -> @_entities[id].max_mp
  get_race: (id) -> @_entities[id].race
  get_class: (id) -> @_entities[id].class
  get_gender: (id) -> @_entities[id].gender
  get_speed: (id) -> @_entities[id].speed
  get_level: (id) -> @_entities[id].level
  get_short_description: (id) -> @_entities[id].short_description
  get_skills: (id) -> @_entities[id].skills
  at_max_hp: (id) -> @get_hp(id) == @get_max_hp(id)
  at_max_mp: (id) -> @get_mp(id) == @get_max_mp(id)
  is_dead: (id) -> @_entities[id].dead
  is_blocked: (i, j) -> @is_wall(i, j) or @is_creature(i, j)
  is_creature: (i, j) -> @_map.exists i, j, CREATURES
  is_wall: (i, j) -> @_map.exists i, j, WALLS
  is_rubble: (i, j) -> @_map.at i, j, WALLS, 'rubble'
  is_entrance: (i, j) -> @_map.at i, j, FLOORS, 'entrance'
  is_exit: (i, j) -> @_map.at i, j, FLOORS, 'exit'
  get_data: (x, y) -> @_map.get_stack x, y

  is_blocked_in_dir: (i, j, dir) ->
    [ni, nj] = @get_adjacent i, j, dir
    @is_blocked ni, nj

  is_creature_in_dir: (i, j, dir) ->
    [ni, nj] = @get_adjacent i, j, dir
    @is_creature ni, nj

  monster_count: ->
    count = 0

    @each_monster (id) ->
      count += 1

    count

  get_by_pos: (i, j) ->
    found = null

    $.each @_entities, (idx, entity) ->
      found = entity.id if entity.x == i and entity.y == j

    found

  get_closest_creature: (id, opts={}) ->
    [i, j] = @get_pos id
    range = opts.range ? 999

    closest = null
    distance = null

    @each_monster (monster) =>
      [mi,mj] = @get_pos monster
      dist = @get_distance i, j, mi, mj

      if dist <= range and (not closest or dist < distance)
        closest = monster
        distance = dist

    closest
    
  get_nearby_creatures: (id, opts={}) ->
    [i, j] = @get_pos id
    range = opts.range ? 999
    
    range_sq = range * range
    
    nearby_creatures = []

    @each_monster (monster_id) =>
      return if monster_id == @player_id
      
      [mi,mj] = @get_pos monster_id
      dist = @get_euclid_distance_sq i, j, mi, mj

      if dist <= range_sq
        nearby_creatures.push @get_actor monster_id

    nearby_creatures

  find_in_direction: (i, j, dir, cb) ->
    [oi, oj] = @_offset_by_dir dir

    n = 0
    loop
      if cb i, j, n
        return [i, j]

      else
        [i, j] = [i+oi, j+oj]
        n += 1

  pos_in_direction: (i, j, dir, range=1) ->
    [oi, oj] = @_offset_by_dir dir
    [i + (oi * range), j + (oj * range)]

  get_distance: (i, j, ni, nj) ->
    Math.abs(ni-i) + Math.abs(nj-j)
    
  get_euclid_distance_sq: (i, j, ni, nj) ->
    idiff = ni-i
    jdiff = nj-j
    idiff * idiff + jdiff * jdiff

  get_adjacent_pos: (id, dir) ->
    [i, j] = @get_pos id
    @get_adjacent i, j, dir

  get_adjacent: (i, j, dir) ->
    [oi, oj] = @_offset_by_dir dir
    [i+oi, j+oj]

  get_all_adjacent_pos: (i, j) ->
    positions = []

    $.each [-1..1], (e, oi) =>
      $.each [-1..1], (e, oj) =>
        unless oi == 0 and oj == 0
          positions.push [i+oi, j+oj]

    positions

  get_adjacent_positions: (id) ->
    @get_all_adjacent_pos @get_pos(id)...

  general_direction: (id, ti, tj) ->
    [i, j] = @get_pos id
    @_dir_by_offset ti-i, tj-j

  rotate_right: (dir) ->
    RIGHT[dir]

  rotate_left: (dir) ->
    LEFT[dir]

  flip_dir: (dir) ->
    REVERSE[dir]

  random_empty_space: ->
    @_random_space (i, j) =>
      not @is_blocked(i, j)

  # ACTIONS

  msg: (id, msg) ->
    if id == @player_id
      overflow = @output.length - (MAX_OUTPUT_LENGTH - 1)

      if overflow > 0
        @output = @output[overflow..]

      player_actor = @get_actor @player_id
      
      @output.push {turn_count: player_actor.turn_count, message: msg }

  shout_by: (id, msg) ->
    return if id == @player_id
    @msg @player_id, msg

  set_pos: (id, i, j) ->
    [oi, oj] = @_entities[id].pos()
    @_map.clear_tile oi, oj, CREATURES

    @_entities[id].set_pos i, j
    @_map.set_tile i, j, CREATURES, @_entities[id]

  damage: (id, amount) ->
    entity = @_entities[id]
    entity.hp -= amount

    if entity.hp <= 0
      entity.hp = 0
      entity.dead = true

  remove_mp: (id, amount) ->
    entity = @_entities[id]
    entity.mp -= amount

    if entity.mp <= 0
      entity.mp = 0

  remove: (id) ->
    [i, j] = @_entities[id].pos()
    delete @_entities[id]

    @_map.clear_tile i, j, CREATURES

  set_off_triggers: (id) ->
    [i, j] = @get_pos id

    trigger = @get_trigger i, j
    trigger id if trigger

  give_skill: (id, skill) ->
    entity = @_entities[id]
    entity.add_skill skill
    if id == @player_id
      SoundEffects.get().play_skill_gained();

  unlock_exit: ->
    @exit_locked = false

  restore_hp: (id, amount) ->
    entity = @_entities[id]
    
    if !entity
      return
    
    entity.hp += amount

    if entity.hp > entity.max_hp
      entity.hp = entity.max_hp
    if id == @player_id
      SoundEffects.get().play_restore_hp();

  restore_mp: (id, amount) ->
    entity = @_entities[id]
    
    if !entity
      return
    
    entity.mp += amount

    if entity.mp > entity.max_mp
      entity.mp = entity.max_mp
    if id == @player_id
      SoundEffects.get().play_restore_mp();

  grant_xp: (id, amount) ->
    entity = @_entities[id]
    
    if !entity
      return
    
    entity.xp += amount

    if entity.xp >= 1
      entity.level_up()
      @msg id, "You leveled up!"
      if id == @player_id
        SoundEffects.get().play_level_up();
      
  grant_gold: (id, amount) ->
    entity = @_entities[id]
    if entity and amount
      entity.gold += amount
      if id == @player_id
        @msg id, "You collect $#{amount} worth of gold!"
        SoundEffects.get().play_coin()
      
  get_player_sight_range: ->
    @_player.sight_range
      
  remove_rubble: (i, j) ->
    GOLD_CHANCE = 5
    GOLD_MEAN = 10 + 10 * (@floor - 1) * 0.2
    GOLD_STDDEV = GOLD_MEAN / 4
    
    if @is_rubble i, j
      @_map.clear_tile i, j, WALLS
      @_map.set_tile i, j, FLOORS, "floor"
      if ROT.RNG.getPercentage() <= GOLD_CHANCE
        amount = RNG.clampedNormal GOLD_MEAN, GOLD_STDDEV
        @put_gold i, j, amount
      
  make_rubble: (i, j) ->
    if @is_wall i, j
      @_map.set_tile i, j, WALLS, "rubble"
      
  clear_player_fov_map: ->
    @_player_fov_map = {}

  get_player_fov_map: ->
    @_player_fov_map
    
  is_visible_to_player: (i, j) ->
    @_player_fov_map[i*@map_width + j]
        
  put_potion: (i, j, type) ->
    key = @_hash_map_key(i, j)
    @_potions_map[key] = type
  
  pickup_potion: (i, j, entity_id) ->
    entity = @_entities[entity_id]
    return unless entity
    
    key = @_hash_map_key(i, j)
    if key of @_potions_map and @_potions_map[key]
      potion = @_potions_map[key]
      amount = RNG.clampedNormal 8 + 8 * (@floor - 1) * 0.1, 2
      if potion == 'hp'
        if entity.hp < entity.max_hp
          @msg entity_id, "You drink the health potion, a warm healing feeling washes over you!"
          @restore_hp entity.id, amount
          delete @_potions_map[key]
      else
        if entity.mp < entity.max_mp
          @msg entity_id, "You drink the magic potion, your toes tingle!"
          @restore_mp entity.id, amount
          delete @_potions_map[key]
          
  get_potion: (i, j) ->
    key = @_hash_map_key(i, j)
    if key of @_potions_map
      @_potions_map[key]
    else
      undefined
    
  put_gold: (i, j, gold_amount) ->
    if gold_amount
      key = @_hash_map_key(i, j)
      @_gold_map[key] ?= 0
      @_gold_map[key] += gold_amount
    
  pickup_gold: (i, j, entity_id) ->
    entity = @_entities[entity_id]
    if entity
      key = @_hash_map_key(i, j)
      gold = @_gold_map[key]
      entity.gold += gold
      delete @_gold_map[key]

      if entity_id == @player_id
        @msg entity_id, "You pick up $#{gold} worth of gold!"
        SoundEffects.get().play_coin()
    
  has_gold: (i, j) ->
    key = @_hash_map_key(i, j)
    key of @_gold_map
    
  _hash_map_key: (i, j) ->
    i * @map_width + j

  # PRIVATE

  _add: (entity) ->
    @_entities[entity.id] = entity
    entity.id

  _random_space: (fn) ->
    tiles = @_find_spaces fn
    $(tiles).random_element()

  _find_spaces: (fn) ->
    fn ?= -> true

    tiles = []

    @_map.each (i, j) =>
      tiles.push [i, j] if fn i, j

    tiles

  _offset_by_dir: (dir) ->
    switch dir
      when 'n' then [-1, 0]
      when 'ne' then [-1, 1]
      when 'e' then [0, 1]
      when 'se' then [1, 1]
      when 's' then [1, 0]
      when 'sw' then [1, -1]
      when 'w' then [0, -1]
      when 'nw' then [-1, -1]
      else
        throw new Error('Unrecognized direction: ' + dir)

  _dir_by_offset: (i, j) ->
    if i > 0 then vert = "s"
    else if i == 0 then vert = ""
    else vert = "n"

    if j > 0 then horz = "e"
    else if j == 0 then horz = ""
    else horz = "w"

    "#{vert}#{horz}"

root.GameState = GameState
root.FLOORS = FLOORS
root.WALLS = WALLS
root.CREATURES = CREATURES
root.TRIGGERS = TRIGGERS
