local ADDON_NAME, ns = ...

-- Tag categories: an icon belongs to the category of its first picture tag (its subject). Words are tags as in
-- scripts/icon_tags.json; their synonym groups (Data/Synonyms.lua) count too when they point at one category.
ns.TAG_CATEGORIES = {
  {
    key = "armor",
    label = "Armor",
    subs = {
      {
        key = "head",
        label = "Head",
        words = "bandana blindfold bonnet circlet crown earmuffs eyepatch glasses goggles hat helm helmet hood "
          .. "mask monocle",
      },
      {
        key = "shoulders",
        label = "Shoulders",
        words = "pauldron shoulder shoulderpad",
      },
      {
        key = "chest",
        label = "Chest",
        words = "breastplate chainmail chest chestplate coat diving dress gown jacket robe tunic vest",
      },
      {
        key = "back",
        label = "Back",
        words = "cape cloak scarf",
      },
      {
        key = "hands",
        label = "Hands",
        words = "gauntlet glove",
      },
      {
        key = "wrists",
        label = "Wrists",
        words = "bracelet bracer",
      },
      {
        key = "waist",
        label = "Waist",
        words = "bandolier belt buckle strap",
      },
      {
        key = "legs",
        label = "Legs",
        words = "kilt legguards legplates pants sarong shorts skirt",
      },
      {
        key = "feet",
        label = "Feet",
        words = "boot sandal shoe snowshoe",
      },
      {
        key = "shirts",
        label = "Shirts & tabards",
        words = "bowtie neckerchief shirt sweater tabard",
      },
      {
        key = "other",
        label = "Other armor",
        words = "armor costume plate spiked",
      },
    },
  },
  {
    key = "weapons",
    label = "Weapons",
    subs = {
      {
        key = "swords",
        label = "Swords",
        words = "blade hilt katana sabre scimitar sword",
      },
      {
        key = "axes",
        label = "Axes",
        words = "axe cleaver decapitate weapon",
      },
      {
        key = "maces",
        label = "Maces & hammers",
        words = "club flail hammer mace mallet nunchaku scepter sledgehammer",
      },
      {
        key = "daggers",
        label = "Daggers",
        words = "dagger knife sai",
      },
      {
        key = "staves",
        label = "Staves",
        words = "staff",
      },
      {
        key = "polearms",
        label = "Polearms",
        words = "glaive halberd harpoon polearm scythe sickle spear spearhead trident warglaive",
      },
      {
        key = "ranged",
        label = "Bows & guns",
        words = "arrow arrowhead blowdart blunderbuss bola boomerang bow bullet cannon cannonball casing chakram "
          .. "chakrum crossbow firearm gun musket pistol rifle shuriken slingshot thrown",
      },
      {
        key = "wands",
        label = "Wands",
        words = "wand",
      },
      {
        key = "fist",
        label = "Fist weapons",
        words = "fist knuckles",
      },
      {
        key = "shields",
        label = "Shields",
        words = "shield",
      },
      {
        key = "offhands",
        label = "Orbs & off-hands",
        words = "offhand orb",
      },
    },
  },
  {
    key = "jewelry",
    label = "Jewelry & gems",
    subs = {
      {
        key = "rings",
        label = "Rings",
        words = "ring setting signet",
      },
      {
        key = "necklaces",
        label = "Necklaces",
        words = "amulet collar medallion necklace pendant talisman",
      },
      {
        key = "gems",
        label = "Gems & crystals",
        words = "amber artifact buoy citrine crystal diamond gem gemstone geode jewel keystone pearl prism shard "
          .. "spire",
      },
    },
  },
  {
    key = "consumables",
    label = "Consumables",
    subs = {
      {
        key = "potions",
        label = "Potions",
        words = "bottle container elixir ether flask gourd potion salve vial",
      },
      {
        key = "food",
        label = "Food & drink",
        words = "acorn apple bacon baguette bamboo banana banquet beer biscuit bowl bread breakfast brew brownie "
          .. "bulb bun butter cabbage cake candy canteen carrot chalice cheese cherry chocolate chowder "
          .. "cinnamon cocoa coconut cookie corn cornucopia cranberries crepe croissant cup cupcake doughnut "
          .. "drink drumstick dumpling egg feast fishcake flan flatbread flour food fried fries fruit garlic "
          .. "glass goblet grapes ham haunch honeycomb jerky kale kebab leek loaf lollipop meat melon muffin "
          .. "mug noodles nut olive onion orange parsnip peach pepper pie pitcher pizza platter plum "
          .. "pomegranate popcorn potato pretzel pudding pumpkin radish ravioli ribs rice roast roll salad "
          .. "salmon salt sandwich sausage scallion shank skewer smoothie smores sorbet soup soy spice "
          .. "springrolls squash steak steam stein stew stirfry strawberry stuffing sugar sushi sweet table "
          .. "tankard tart tartare tea teapot tempura tenders toast tomato tongue turnip watermelon waterskin "
          .. "yogurt",
      },
      {
        key = "bandages",
        label = "Bandages",
        words = "bandage medkit",
      },
    },
  },
  {
    key = "materials",
    label = "Materials",
    subs = {
      {
        key = "ore",
        label = "Ore & stone",
        words = "bar block brimstone chunk ingot iron metal nugget ore platinum rock rubble slate stack stone "
          .. "weight whetstone",
      },
      {
        key = "plants",
        label = "Plants",
        words = "bark berry blossom bough bouquet bramble branch cactus clover coral dandelion flower flytrap "
          .. "forest frostweed ginseng grass herb kelp leaf lichen lily log lotus marigolds moss mushroom "
          .. "nightshade orchid petal plant pod root rose sage seastalk seed spore sprout stalk stem stump "
          .. "sugarcane thistle thorn tree vine wheat wood",
      },
      {
        key = "cloth",
        label = "Cloth & leather",
        words = "blanket bolt cloth fabric fur hide leather pelt scale scrap silk sinew spiderweb spool thread "
          .. "web wool yarn",
      },
      {
        key = "dust",
        label = "Dust & ink",
        words = "ash dust gunpowder ink inkwell pigment pollen powder sand warpaint",
      },
    },
  },
  {
    key = "creatures",
    label = "Creatures",
    subs = {
      {
        key = "dragons",
        label = "Dragons",
        words = "dragon dragonhawk drake proto rylak whelp wyrm wyvern",
      },
      {
        key = "beasts",
        label = "Beasts",
        words = "alpaca armadillo basilisk bat bear beast beaver boar bull camel capybara cat chihuahua "
          .. "clefthoof compy corgi cow deer devilsaur dinosaur direhorn dog donkey elekk elephant fawn "
          .. "felsaber ferret fox goat gorilla hare hedgehog hippo horse hound hyena jaguar kitten kodo lion "
          .. "lynx mammoth marmoset mastiff mole monkey moose mouse muskox otter owlbear ox panda pangolin "
          .. "panther pegasus pig piglet pinecone porcupine prairie prairiedog pterodactyl pterrordax rabbit "
          .. "raccoon ram raptor rat rhino saber sabertooth sheep skunk sloth squirrel stag talbuk tiger "
          .. "triceratops unicorn warg warp wolf yak yeti zebra",
      },
      {
        key = "birds",
        label = "Birds",
        words = "albatross bird chick chicken cockatrice crane crow duck duckling eagle griffon gryphon hawk "
          .. "hawkstrider hippogryph kakapo owl parrot peacock penguin phoenix raven roc seagull strider "
          .. "toucan turkey vulture woodpecker",
      },
      {
        key = "water",
        label = "Water creatures",
        words = "ammonite anglerfish axolotl clam crab eel fish frog jellyfish lobster makrura murloc naga "
          .. "nautilus octopus oyster pup seahorse seashell shark shell shrimp slug squid starfish stingray "
          .. "tentacle toad trilobite turtle",
      },
      {
        key = "insects",
        label = "Insects & critters",
        words = "bee beetle borer bug butterfly caterpillar cockroach cricket dragonfly firefly fly insect "
          .. "isopod ladybug larva louse maggot mantid mantis moth pupa roach roly scarab scorpion silithid "
          .. "snail spider swarmer tarantula tick wasp worm",
      },
      {
        key = "reptiles",
        label = "Reptiles",
        words = "cobra crocodile crocolisk lizard salamander serpent snake",
      },
      {
        key = "undead",
        label = "Demons & undead",
        words = "cerberus demon doomguard gargoyle ghost ghoul gravestone imp mummy reaper screaming skeleton "
          .. "skull spirit tombstone undead voidwalker zombie",
      },
      {
        key = "other",
        label = "Other creatures",
        words = "beholder chimera crawler creature creeper elemental gnoll golem gronn kirin kobold mandrake maw "
          .. "mech mechanical monster moonkin naaru pixiu podling quilin ragnaros ravager robot shredder "
          .. "snobold stalker swamp treant vessel zergling",
      },
      {
        key = "mounts",
        label = "Mounts & pets",
        words = "barding chess flyer mount pet",
      },
    },
  },
  {
    key = "people",
    label = "People & body",
    words = "angel archer arm avatar bloody body brain clones druid dwarf ear elf eye eyeball face figure "
      .. "foot gnome goblin gruntling guts hand head heart hooded human hunter intestine jump kick knight "
      .. "leg lips mage man meditation monk mouth muscle nerves ogre orc organ person pilgrim pirate "
      .. "portrait priest queen rider rogue shaman silhouette squire stomach tauren trio troll tumor "
      .. "valkyr walrus warlock warrior witch woman",
  },
  {
    key = "parts",
    label = "Animal parts",
    words = "antler beak bone carapace chitin claw fang feather fin hoof horn husk jaw paw spine spinneret "
      .. "tail tooth tusk wing",
  },
  {
    key = "magic",
    label = "Magic & effects",
    words = "acid air arc arcane backdraft beam blackhole blast blob blood breath bubble burst cloud cocoon "
      .. "comet constellation core crack dome drop earth earthquake eclipse ember energy essence "
      .. "explosion fire fireball flame flare frost frostbolt galaxy glacier glowing glyph gold ground "
      .. "halo hoop hunting ice inferno karma lasso lava life light lightning magic maim meteor missile "
      .. "mist molten moon night nova oil ooze overcharge particles planet portal quicksand rain ray rift "
      .. "ripple rockfall rune sandstorm shadow sigil slam slash slime smoke snow snowball snowflake "
      .. "spark sparkle sphere spike spiral splash splinter star streak sun sunburst swirl swoosh "
      .. "teleport tendril tornado vein void volcano vortex water wave whirlwind wind wisp wrap",
  },
  {
    key = "paper",
    label = "Books & paper",
    words = "blueprint book card clipboard contract deck envelope letter map math note paper papyrus "
      .. "parchment poster quill scroll stele tablet ticket tome wrapping",
  },
  {
    key = "bags",
    label = "Bags & containers",
    words = "backpack bag barrel basket birdcage box bucket cage canister cracker crate drawer gift jar "
      .. "lockbox lunchbox pack package pail pouch present quiver sack tinderbox treasure urn vase",
  },
  {
    key = "tools",
    label = "Tools & objects",
    words = "airship altar anchor anvil arena bait ball balloon basketball battery battleground bed bedroll "
      .. "bell bellows binoculars birdhouse board boat bobber bomb boombox brazier broom brush building "
      .. "button camera campfire candle carpet carrier cart castle catapult cauldron chain chair chime "
      .. "chisel chopper city clamp clock cogwheel coil collector comb communicator compass computer cube "
      .. "cylinder device dice discoball distiller doll donut drill drone drum dumbbell dungeon dynamite "
      .. "emitter engine fan figurine file film firecracker fishing flamethrower flute flying football "
      .. "fork frame gadget gameboard gate gear giant gizmo glider globe gondola gong grenade grindstone "
      .. "guitar gyrocopter handle harness harp hearthstone helicopter hobby hoe hook horseshoe hourglass "
      .. "house hovercraft idol incense injector kettle key keychain kite ladder lantern leash lens "
      .. "lightbulb loveseat lure machine magnet magnifier magnifying manacles matchbook mine mirror "
      .. "module mortar motorcycle multitool needle net noose oilcan pan partition pedestal pickaxe "
      .. "pillar pillow pipe pitchfork popper pot power pyramid raft rake razor remote rocket rod roller "
      .. "rolling room rope saw sawblade scarecrow scissors scope screw screwdriver searchlight sextant "
      .. "sharpening ship shovel siege skiff sled sleigh snowman soccer spanner speaker spoon sprayer "
      .. "spring spyglass stabilizer statue stirrup stopwatch submarine sundial surfboard syringe tank "
      .. "telescope temple tent tesla throne thumbtack tiki tongs tool toolbox torch totem tower train "
      .. "trap triangle trigger trinket trophy trowel trumpet tube turret vehicle vending voodoo wall "
      .. "watch watering wheel whip whistle windmill wire wrench zeppelin",
  },
  {
    key = "symbols",
    label = "Symbols",
    words = "alliance badge banner chevron chip circle cliff coin crescent crest cross crosshair dark disc "
      .. "dna emblem filigree flag hexagon horde knot landscape mark medal minus mountain number pattern "
      .. "pawprint pennant pin plus puzzle question ribbon seal symbol tapestry target yin zzz",
  },
}
