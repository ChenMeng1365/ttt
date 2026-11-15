#coding:utf-8
=begin
tt.rb ~~ 九宫幻卡 TripleTriad 文字版
  FF8 九宫牌局, 终端对弈, 蓝方先手.
  (Web 版 tt.html 为红左蓝右对坐布局, 终端版受列宽限手牌上下排布)

USE:
  ruby tt.rb [选项]
  --pvp     双人对局, 红方也由人执子 (默认红方是 AI)
  --demo    双方全 AI 自动演示
  --same    Same 规则: 两个接触面同值齐翻
  --plus    Plus 规则: 两个接触面同和齐翻
  --wall    出界方向视为 A 值 (配合 same/plus 参与判定)
  --element 元素规则: 随机 1-3 格带元素, 落牌同元素+1, 异或无元素-1
  --sudden  骤亡规则: 平局时随机翻面一张场上牌出局, 重比至分胜负
  --nocombo 关闭连锁: Same/Plus 翻起的牌不再连锁施压 (默认开)
  --trade=one|diff|direct|all  交换规则: 赢家拿 1 张 / 差额张 / Direct 各拿己色 / 全部
  --pick    蓝方自选卡组 (列出 110 张表, 红方仍随机)
  --mono    强制关色 (终端不认 ANSI 时用; 平时不加也会自动探测)
  --color   强制开色 (Windows Terminal 等现代终端默认自动开)

卡池: 110 张, FF8 原作全图鉴 (2026-11 经 tt-cards/dataset 校准);
  数据行 `名 上 右 下 左 元素`, 名可含空格, 无元素记 -.

规则:
  双方各持 5 张牌轮流入场, 牌面四向数值 [上右下左], A 即 10.
  卡面渲染为五行小方框, 数值嵌在上边/左右边/下边, 一眼即识.
  蓝卡单线框, 红卡双线框, 颜色关闭时凭框型可辨.
  新牌接触面数值大于邻牌对应面 => 翻之为己方颜色.
  Same/Plus 翻起的牌连锁施压 (combo, 可关), 基本翻转不连锁.
  元素修正只作用于新落牌的本回合进攻, 连锁牌用原始值.
  十牌九格, 后手必滞 1 张在手中: 终局先手计场上牌色,
  后手计场上牌色加手中滞留牌, 多者胜.
  交换规则: 赢家按 One/Diff/All 从输家 (场上+滞留) 拿卡, 平局不交换.

出牌格式: `牌号 位置`, 例 `3 5` => 第3张牌落5号位
  1 2 3
  4 5 6
  7 8 9
=end

#### card ####

# 牌面四值 [上右下左], A=10; el 为元素 (备 Elemental 规则, 暂未参战)
class Card
  attr_reader :nm, :vl, :el
  def initialize nm, vl, el=nil
    @nm = nm
    @vl = vl
    @el = el
  end
  # 四值串 "145A"
  def to_s
    @vl.map{|v|"%X"%v}.join
  end
end

class Symbol
  # func: :b/:r => 蓝/红
  def who
    self == :b ? "蓝" : "红"
  end
end

#### pool ####

# 卡池 110 张从脚本尾部内嵌文档读入: `名 上 右 下 左 元素`
# 名可含空格 (取前段拼回), A 记 10, 无元素记 -
CARDS = DATA.read.split("\n").inject([]) do|a, ln|
  t = ln.split
  if t.size >= 6 and t[-5, 4].all?{|v| v =~ /^[1-9A]$/} and t[-1] =~ /^[\w-]+$/
    a << Card.new(t[0, t.size-5].join(" "), t[-5, 4].map{|v|eval("0x"+v)}, t[-1] == "-" ? nil : t[-1])
  end
  a
end
CARDS.size == 110 or abort "!! 卡池 #{CARDS.size} != 110"
ELEMENTS = %w[fire ice thunder water earth poison wind holy]

#### board ####
module Triad
  module_function

  # 方向: 0上 1右 2下 3左, 相对面 = (d+2)%4
  # CALL: nbr i #=> [[邻位, 方向], ...] 只含盘内邻位
  def nbr i
    r, c = i/3, i%3
    a = []
    a << [i-3, 0] if r > 0
    a << [i+1, 1] if c < 2
    a << [i+3, 2] if r < 2
    a << [i-1, 3] if c > 0
    a
  end

  # 结算: 落 i 位的全部翻转, 纯读盘不落子 (AI 预演算也用它)
  # ce 为元素格表; 元素修正只作用于新落牌本回合, 连锁牌用原始值
  # CALL: settle bd, i, cd, sd, rl, ce #=> [翻转位, ...]
  def settle bd, i, cd, sd, rl, ce=nil
    fl = {}
    fv = (ce && ce[i]) ? cd.vl.map{|v| cd.el == ce[i] ? v + 1 : v - 1} : cd.vl
    # 基本翻转: 接触面压过邻牌
    nbr(i).each do|np, d|
      t = bd[np]
      t and t[:sd] != sd and fv[d] > t[:cd].vl[(d+2)%4] and fl[np] = true
    end
    if rl[:same] or rl[:plus]
      # 接触表 [邻位, 新面值, 邻面值, 邻色], 只收有牌的邻位
      ct = nbr(i).select{|np, d| bd[np]}.map do|np, d|
        t = bd[np]
        [np, fv[d], t[:cd].vl[(d+2)%4], t[:sd]]
      end
      # 墙面: 出界方向视为 A, 参与判定但无从翻起
      if rl[:wall]
        ex = nbr(i).map{|np, d| d}
        4.times{|d| ex.include?(d) or ct << [nil, fv[d], 10, nil]}
      end
      que = []   # combo 连锁队列
      if rl[:same]
        eq = ct.select{|np, a, b, s| a == b}
        eq.size > 1 and eq.each do|np, a, b, s|
          np and s != sd and !fl[np] and fl[np] = true and que << np
        end
      end
      if rl[:plus]
        sum = Hash.new{|h, k| h[k] = []}
        ct.each{|np, a, b, s| sum[a + b] << [np, s]}
        sum.values.select{|ls| ls.size > 1}.each do|ls|
          ls.each do|np, s|
            np and s != sd and !fl[np] and fl[np] = true and que << np
          end
        end
      end
      # combo: same/plus 翻起的牌连锁施压, 基本比较继续传播 (可关)
      if rl[:combo]
        while s = que.shift
          sc = bd[s][:cd]
          nbr(s).each do|np, d|
            t = bd[np]
            next unless t and t[:sd] != sd and !fl[np]
            sc.vl[d] > t[:cd].vl[(d+2)%4] and fl[np] = true and que << np
          end
        end
      end
    end
    fl.keys
  end

  # 落子并生效
  # CALL: put! bd, i, cd, sd, rl, ce #=> 翻转数
  def put! bd, i, cd, sd, rl, ce=nil
    bd[i] = {cd: cd, sd: sd}
    fl = settle bd, i, cd, sd, rl, ce
    fl.each{|np| bd[np][:sd] = sd}
    fl.size
  end

  # CALL: count bd #=> [蓝数, 红数]; 骤亡翻面 (dead) 的牌不计
  def count bd
    bd.inject([0, 0]) do|(b, r), t|
      next [b, r] unless t and !t[:dead]
      t[:sd] == :b ? [b+1, r] : [b, r+1]
    end
  end

  #### render ####

  # CALL: paint s, sd #=> 着色串
  def paint s, sd
    return s if $mono
    "%s%s%s"%[sd == :b ? "\e[1;34m" : "\e[1;31m", s, "\e[0m"]
  end

  # 卡面五行, 数值布局: 上边/左右边/下边, A 即 10
  # 蓝卡单线框, 红卡双线框, mono 下也一眼可辨
  # CALL: card_rows cd, sd #=> [五行]
  def card_rows cd, sd
    u, r, d, l = cd.vl
    e = sd == :b ? ["┌─────┐", "│", "└─────┘"] : ["╔═════╗", "║", "╚═════╝"]
    a = [e[0],
         e[1] + "  %X  "%u + e[1],
         e[1] + "%X   %X"%[l, r] + e[1],
         e[1] + "  %X  "%d + e[1],
         e[2]]
    a.map{|ln| paint ln, sd}
  end

  # CALL: cell_rows bd, i #=> 卡面五行; 空位则中行嵌位置号
  def cell_rows bd, i
    t = bd[i]
    return card_rows t[:cd], t[:sd] if t
    ["┌─────┐", "│     │", "│  %d  │"%(i+1), "│     │", "└─────┘"]
  end

  # CALL: show bd #=> nil
  def show bd
    puts "        1        2        3"
    3.times do|r|
      rows = Array.new 5, ""
      3.times do|c|
        cr = cell_rows bd, r*3+c
        5.times{|k| rows[k] += cr[k] + "  "}
      end
      5.times do|k|
        puts (k == 2 ? "  %d  "%(r+1) : "     ") + rows[k]
      end
    end
  end

  # 每卡占 14 列, 七行: 编号/五行卡面/牌名, 牌名对准卡心
  # CALL: hand_show hand, sd #=> nil
  def hand_show hand, sd
    puts "  %s方手牌:"%sd.who
    return if hand.empty?
    rows = Array.new 7, ""
    hand.each_with_index do|cd, i|
      rows[0] += "  " + paint("[%d]"%(i+1), sd) + " "*9
      cr = card_rows cd, sd
      5.times{|k| rows[k+1] += cr[k] + " "*7}
      dn = cd.nm.size > 13 ? cd.nm[0, 13] : cd.nm   # 长名截 13, 防手牌槽错位
      n = dn.size
      l = [3 - n/2, 0].max
      rows[6] += " "*l + paint(dn, sd) + " "*(14 - n - l)
    end
    rows.each{|ln| puts "  " + ln}
  end

  # CALL: rule_tag rl #=> 规则串
  def rule_tag rl
    t = ["基本"]
    rl[:elemental] and t << "Elemental"
    rl[:same] and t << "Same"
    rl[:plus] and t << "Plus"
    rl[:wall] and t << "Wall"
    rl[:combo] or t << "无连锁"
    t.join "+"
  end

  #### ai ####

  # 贪心评估: 翻牌收益 + 落位权重 + 弱牌先出的微倾向
  # CALL: ai_pick bd, hand, sd, rl, ce #=> [牌, 位]
  def ai_pick bd, hand, sd, rl, ce=nil
    pv = [3, 2, 3, 2, 4, 2, 3, 2, 3]   # 角3 边2 中4
    best, bg = nil, -99.0
    hand.each do|cd|
      9.times do|i|
        next if bd[i]
        g = settle(bd, i, cd, sd, rl, ce).size*10 + pv[i] + rand - cd.vl.inject(:+)*0.05
        if g > bg
          best, bg = [cd, i], g
        end
      end
    end
    best
  end

  #### console ####

  # CALL: ask bd, hand, sd #=> [牌, 位]; q 退出, h 帮助
  def ask bd, hand, sd
    loop do
      print "%s方出牌[牌号 位置] (h帮助 q退出)> "%sd.who
      STDOUT.flush
      ln = STDIN.gets
      exit unless ln
      ln = ln.strip
      if ln =~ /^q$/i
        puts "对局中止."
        exit
      end
      if ln =~ /^h$/i
        puts "  出牌: `牌号 位置`, 例 `3 5` = 第3张牌落5号位; 布局 123/456/789, 牌值序 上右下左."
        next
      end
      t = ln.split
      next unless t.size == 2 and t.all?{|x|x =~ /^\d+$/}
      hi, i = t[0].to_i, t[1].to_i
      next unless hi >= 1 and hi <= hand.size
      next unless i >= 1 and i <= 9 and !bd[i-1]
      return [hand[hi-1], i-1]
    end
  end

  # 自选卡组: 先列 110 张表, 再输 5 个编号 (0=随机补位)
  # CALL: pick_hand #=> [卡, ...×5]
  def pick_hand
    puts "  === 卡池表 (编号 名 [上右下左] 元素) ==="
    CARDS.each_with_index do|c, k|
      printf("  %3d %-16s %-4s %s\n", k+1, c.nm, c.to_s, c.el || "-")
    end
    puts "  === 输入 5 个编号 (空格分隔, 0=随机) ==="
    loop do
      print "  选卡> "
      STDOUT.flush
      t = STDIN.gets.to_s.split.map{|x| x.to_i}
      next puts "  !! 需 5 个编号" unless t.size == 5
      next puts "  !! 编号 0~110" unless t.all?{|x| x >= 0 and x <= CARDS.size}
      next puts "  !! 编号重复" unless t.uniq.size == t.size
      h = t.map{|x| x == 0 ? nil : CARDS[x - 1]}.compact
      (CARDS - h).shuffle.first(5 - h.size).each{|c| h << c}
      return h
    end
  end

  #### main ####

  # CALL: run rl, pvp, demo, pick #=> nil
  def run rl, pvp, demo, pick
    ce = nil
    if rl[:elemental]
      ce = Array.new 9
      (1 + rand(3)).times{ ce[rand(9)] = ELEMENTS.sample }
    end
    deck = CARDS.shuffle
    hand = {b: deck[0, 5], r: deck[5, 5]}
    if pick
      hand[:b] = pick_hand
      hand[:r] = (CARDS - hand[:b]).shuffle.first(5)
    end
    bd = Array.new 9
    sd = :b
    puts "", "==== 九宫幻卡 TripleTriad 开局 ====  规则[%s·%s]  %s"%[rule_tag(rl), rl[:trade], demo ? "演示模式" : "蓝方先手"], ""
    loop do
      show bd
      b, r = count bd
      es = ce ? ce.each_with_index.select{|e, k| e}.map{|e, k| "%d号=%s"%[k+1, e]}.join(" ") : ""
      puts "  场面 蓝%d : 红%d   手中 蓝%d 红%d%s"%[b, r, hand[:b].size, hand[:r].size, es.empty? ? "" : "   元素格 " + es]
      hand_show hand[:b], :b
      hand_show hand[:r], :r
      if demo
        cd, i = ai_pick bd, hand[sd], sd, rl, ce
        sleep 0.4
      elsif sd == :r and !pvp
        cd, i = ai_pick bd, hand[sd], sd, rl, ce
      else
        cd, i = ask bd, hand[sd], sd
      end
      n = put! bd, i, cd, sd, rl, ce
      hand[sd].delete cd
      puts "  => %s方落 %-14s[%s] 于位%d, 翻转%d张"%[sd.who, cd.nm, cd, i+1, n], ""
      bd.include?(nil) or break
      sd = sd == :b ? :r : :b
    end
    # 十牌九格, 后手必滞 1 张在手: 先手只计场上, 后手另计手中滞留牌
    b, r = count bd
    r += hand[:r].size
    show bd
    puts "", "==== 终局 ===="
    # 骤亡: 平局时逐张随机翻面场上牌出局, 直至分出胜负
    win = b > r ? :b : b < r ? :r : nil
    if win.nil? and rl[:sd]
      loop do
        live = bd.each_with_index.select{|t, k| t and !t[:dead]}
        break if live.empty?
        t, k = live.sample
        t[:dead] = true
        puts "  骤亡: %d号 %s 翻面出局"%[k+1, t[:cd].nm]
        b, r = count bd
        r += hand[:r].size
        if b != r
          win = b > r ? :b : :r
          break
        end
      end
      show bd
    end
    puts "  蓝方 %d 张 : 红方 %d 张 (红含手中滞留%d张)"%[b, r, hand[:r].size]
    puts b > r ? "  *** 蓝方胜 ***" : b < r ? "  *** 红方胜 ***" : "  *** 平局 ***"
    # 交换: Direct 各自拿走己色牌(平局也换); One/Diff/All 赢家从输家拿, 平局不换
    if rl[:trade] == "direct"
      bp = bd.select{|t| t and !t[:dead] and t[:sd] == :b}.map{|t| t[:cd].nm}
      rp = bd.select{|t| t and !t[:dead] and t[:sd] == :r}.map{|t| t[:cd].nm} + hand[:r].map{|c| c.nm}
      puts "  交换[Direct]: 蓝方获得 %s / 红方获得 %s"%[bp.empty? ? "—" : bp.join(", "), rp.empty? ? "—" : rp.join(", ")]
    elsif win
      lose = win == :b ? :r : :b
      pool = bd.select{|t| t and !t[:dead] and t[:sd] == lose}.map{|t| t[:cd]} + hand[lose]
      pool.sort_by!{|c| -c.vl.inject(:+)}
      n = rl[:trade] == "all" ? pool.size : rl[:trade] == "diff" ? (b - r).abs : 1
      n = [n, pool.size].min
      puts "  交换[%s]: %s方获得 %s"%[{ "one" => "One", "diff" => "Diff", "all" => "All" }[rl[:trade]], win.who, pool[0, n].map{|c| c.nm}.join(", ")]
    else
      puts "  平局, 无交换."
    end
  end
end

#### entrance ####

# Windows conhost 默认不认 ANSI: 能开 VT 就开, 开不动自动退 mono
# CALL: vt_try #=> bool
def vt_try
  return false unless STDOUT.tty? and RUBY_PLATFORM =~ /mswin|mingw/
  require 'fiddle'
  k = Fiddle.dlopen 'kernel32.dll'
  g = Fiddle::Function.new k['GetStdHandle'], [Fiddle::TYPE_LONG], Fiddle::TYPE_LONG
  gm = Fiddle::Function.new k['GetConsoleMode'], [Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP], Fiddle::TYPE_LONG
  sm = Fiddle::Function.new k['SetConsoleMode'], [Fiddle::TYPE_LONG, Fiddle::TYPE_LONG], Fiddle::TYPE_LONG
  h = g.call -11
  m = [0].pack 'L'
  return false if gm.call(h, m).zero?
  sm.call(h, m.unpack1('L') | 0x4) != 0
rescue
  false
end

STDOUT.sync = true   # 控制台即时出屏, 免缓冲吞帧
$mono = ARGV.include? '--mono'
if ARGV.include? '--color'
  $mono = false
elsif !$mono
  $mono = !(STDOUT.tty? and (ENV['WT_SESSION'] or ENV['TERM'] or ENV['ANSICON'] or vt_try))
end
rl = {same: ARGV.include?('--same'), plus: ARGV.include?('--plus'), wall: ARGV.include?('--wall'),
      combo: !ARGV.include?('--nocombo'), elemental: ARGV.include?('--element'), sd: ARGV.include?('--sudden')}
tr = (ARGV.find{|a| a =~ /^--trade=/} || "").sub(/^--trade=/, "")
rl[:trade] = %w[one diff direct all].include?(tr) ? tr : "one"
if :main
  Triad.run rl, ARGV.include?('--pvp'), ARGV.include?('--demo'), ARGV.include?('--pick')
end

__END__
Geezard 1 4 1 5 -
Funguar 5 1 1 3 -
Bite Bug 1 3 3 5 -
Red Bat 6 1 1 2 -
Blobra 2 3 1 5 -
Gayla 2 1 4 4 thunder
Gesper 1 5 4 1 -
Fastitocalon-F 3 5 2 1 earth
Blood Soul 2 1 6 1 -
Caterchipillar 4 2 4 3 -
Cockatrice 2 1 2 6 thunder
Grat 7 1 3 1 -
Buel 6 2 2 3 -
Mesmerize 5 3 3 4 -
Glacial Eye 6 1 4 3 ice
Belhelmel 3 4 5 3 -
Thrustaevis 5 3 2 5 wind
Anacondaur 5 1 3 5 poison
Creeps 5 2 5 2 thunder
Grendel 4 4 5 2 thunder
Jelleye 3 2 1 7 -
Grand Mantis 5 2 5 3 -
Forbidden 6 6 3 2 -
Armadodo 6 3 1 6 earth
Tri-Face 3 5 5 5 poison
Fastitocalon 7 5 1 3 earth
Snow Lion 7 1 5 3 ice
Ochu 5 6 3 3 -
SAM08G 5 6 2 4 fire
Death Claw 4 4 7 2 fire
Cactuar 6 2 6 3 -
Tonberry 3 6 4 4 -
Abyss Worm 7 2 3 5 earth
Turtapod 2 3 6 7 -
Vysage 6 5 4 5 -
T-Rexaur 4 6 2 7 -
Bomb 2 7 6 3 fire
Blitz 1 6 4 7 thunder
Wendigo 7 3 1 6 -
Torama 7 4 4 4 -
Imp 3 7 3 6 -
Blue Dragon 6 2 7 3 poison
Adamantoise 4 5 5 6 earth
Hexadragon 7 5 4 3 fire
Iron Giant 6 5 6 5 -
Behemoth 3 6 5 7 -
Chimera 7 6 5 3 water
PuPu 3 A 2 1 -
Elastoid 6 2 6 7 -
GIM47N 5 5 7 4 -
Malboro 7 7 4 2 poison
Ruby Dragon 7 2 7 4 fire
Elnoyle 5 3 7 6 -
Tonberry King 4 6 7 4 -
Wedge, Biggs 6 6 2 7 -
Fujin Raijin 2 8 8 4 -
Elvoret 7 8 3 4 wind
X-ATM092 4 8 7 3 -
Granaldo 7 2 8 5 -
Gerogero 1 8 8 3 poison
Iguion 8 2 8 2 -
Abadon 6 8 4 5 -
Trauma 4 8 5 6 -
Oilboyle 1 8 4 8 -
Shumi 6 5 8 4 -
Krysta 7 5 8 1 -
Propagator 8 4 4 8 -
Jumbo Cactuar 8 8 4 4 -
Tri-Point 8 5 2 8 thunder
Gargantua 5 6 6 8 -
Mobile Type 8 8 6 7 3 -
Sphinxara 8 3 5 8 -
Tiamat 8 8 5 4 -
BGH251F2 5 7 8 5 -
Red Giant 6 8 4 7 -
Catoblepas 1 8 7 7 -
Ultima Weapon 7 7 2 8 -
Chubby Chocobo 4 4 8 9 -
Angelo 9 6 7 3 -
Gilgamesh 3 7 9 6 -
MiniMog 9 3 9 2 -
Chicobo 9 4 8 4 -
Quezacotl 2 9 9 4 thunder
Shiva 6 7 4 9 ice
Ifrit 9 6 2 8 fire
Siren 8 9 6 2 -
Sacred 5 1 9 9 earth
Minotaur 9 5 2 9 earth
Carbuncle 8 4 A 4 -
Diablos 5 A 8 3 -
Leviathan 7 A 1 7 water
Odin 8 A 3 5 -
Pandemona A 1 7 7 wind
Cerberus 7 4 6 A -
Alexander 9 A 4 2 holy
Phoenix 7 2 7 A fire
Bahamut A 8 2 6 -
Doomtrain 3 1 A A poison
Eden 4 4 9 A -
Ward A 7 2 8 -
Kiros 6 7 6 A -
Laguna 5 A 3 9 -
Selphie A 8 6 4 -
Quistis 9 6 A 2 -
Irvine 2 6 9 A -
Zell 8 5 A 6 -
Rinoa 4 A 2 A -
Edea A A 3 3 -
Seifer 6 9 A 4 -
Squall A 4 6 9 -
