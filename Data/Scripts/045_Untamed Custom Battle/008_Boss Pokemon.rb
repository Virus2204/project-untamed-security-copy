class Pokemon
  attr_accessor :bossmonMutation
	bossmonMutation = false
	def enableBossPokemonMutation
		bossmonMutation = true
	end  
	def disableBossPokemonMutation
		bossmonMutation = false
	end    

	def toggleBossPokemonMutation
		if !bossmonMutation
			bossmonMutation = true
		else	
			bossmonMutation = false
		end	
	end 		
	
	def isBossPokemon?
		return true if bossmonMutation==true
	end
end

class Battle::Battler
  attr_accessor :remaningHPBars

  def isBossPokemon?
    return (@pokemon) ? @pokemon.isBossPokemon? : false
  end
	
  def pbEffectsOnHPBarBreak(boss) 
    case boss.species
    when :NOCTAVISPA
      if boss.remaningHPBars == 1
        @battle.pbDisplayBrief(_INTL("{1}'s servants were ordered to help!",self.pbThis))
        pbUseExtraMidTurnMove(boss, :DEFENDORDER, boss)
        pbAddNewMoveMidturn(boss, :HEALORDER, 5)
      elsif boss.remaningHPBars == 2
        @battle.pbDisplayBrief(_INTL("{1}'s malice summoned a Dark Zone!",self.pbThis))
        @battle.field.typezone = :DARK
      end
    end
  end

  def pbUseExtraMidTurnMove(boss, move, target)
    # recording the move that the AI choose
    oldCurrentMove = boss.currentMove
    oldLastRoundMoved = boss.lastRoundMoved
    oldOutrage = boss.effects[PBEffects::Outrage]
    # using the extra move
    boss.pbUseMoveSimple(Pokemon::Move.new(move).id, target.index)
    # restoring old move action
    boss.lastRoundMoved = oldLastRoundMoved
    boss.effects[PBEffects::Outrage] = oldOutrage
    boss.currentMove = oldCurrentMove
    @battle.pbJudge
  end

  def pbAddNewMoveMidturn(boss, move, moveid)
    boss.pokemon.moves[moveid] = Pokemon::Move.new(move)                    # create new move
    boss.pokemon.moves[moveid].ppup = 3                                     # increase its max pp
    boss.pokemon.moves[moveid].pp = (boss.pokemon.moves[5].pp * 1.6).floor  # set the new move pp to max
  end

  def pbReduceHP(amt, anim = true, registerDamage = true, anyAnim = true)
    amt = amt.round
    amt = @hp if amt > @hp
    amt = 1 if amt < 1 && !fainted?
    survDmg = false
    if self.isBossPokemon?
      if self.remaningHPBars>0
        amt=amt-1
        survDmg=true
      end
    end
    oldHP = @hp
    self.hp -= amt
    PBDebug.log("[HP change] #{pbThis} lost #{amt} HP (#{oldHP}=>#{@hp})") if amt > 0
    raise _INTL("HP less than 0") if @hp < 0
    raise _INTL("HP greater than total HP") if @hp > @totalhp
    @battle.scene.pbHPChanged(self, oldHP, anim) if anyAnim && amt > 0
    if amt > 0 && registerDamage
      @droppedBelowHalfHP = true if @hp < @totalhp / 2 && @hp + amt >= @totalhp / 2
      @tookDamageThisRound = true
    end
    if survDmg
      self.pbRecoverHP(self.totalhp,true)
      self.remaningHPBars-=1
      case self.remaningHPBars
      when 0
        @battle.pbDisplayBrief(_INTL("{1}'s power is fully unleased!",self.pbThis))
      when 1
        @battle.pbDisplayBrief(_INTL("{1}'s anger is growing!",self.pbThis))
      when 2
        @battle.pbDisplayBrief(_INTL("{1} is starting to get tired!",self.pbThis))
      when 3
        @battle.pbDisplayBrief(_INTL("{1} seems indestructible...",self.pbThis))
      end
      pbEffectsOnHPBarBreak(self)
    end
    return amt
  end
end

class Battle::FakeBattler
  def isBossPokemon?
    return (@pokemon) ? @pokemon.isBossPokemon? : false
  end
end

class Battle::Move
  def pbReduceDamage(user, target)
    damage = target.damageState.calcDamage
    # Substitute takes the damage
    if target.damageState.substitute
      damage = target.effects[PBEffects::Substitute] if damage > target.effects[PBEffects::Substitute]
      target.damageState.hpLost       = damage
      target.damageState.totalHPLost += damage
      return
    end
    # Disguise/Ice Face takes the damage
    return if target.damageState.disguise || target.damageState.iceFace
    # Target takes the damage
    if damage >= target.hp
      damage = target.hp
      # Survive a lethal hit with 1 HP effects
      if nonLethal?(user, target)
        damage -= 1
      elsif target.effects[PBEffects::Endure]
        target.damageState.endured = true
        damage -= 1
      elsif damage == target.totalhp
        if target.hasActiveAbility?(:STURDY) && !@battle.moldBreaker
          target.damageState.sturdy = true
          damage -= 1
        elsif target.hasActiveItem?(:FOCUSSASH) && target.hp == target.totalhp
          target.damageState.focusSash = true
          damage -= 1
        elsif target.hasActiveItem?(:FOCUSBAND) && @battle.pbRandom(100) < 10
          target.damageState.focusBand = true
          damage -= 1
        end
      end
    end
    damage = 0 if damage < 0
    target.damageState.hpLost       = damage
    target.damageState.totalHPLost += damage
  end

  def pbEndureKOMessage(target)
    if target.damageState.disguise
      @battle.pbShowAbilitySplash(target)
      if Battle::Scene::USE_ABILITY_SPLASH
        @battle.pbDisplay(_INTL("Its disguise served it as a decoy!"))
      else
        @battle.pbDisplay(_INTL("{1}'s disguise served it as a decoy!", target.pbThis))
      end
      @battle.pbHideAbilitySplash(target)
      target.pbChangeForm(1, _INTL("{1}'s disguise was busted!", target.pbThis))
      target.pbReduceHP(target.totalhp / 8, false) if Settings::MECHANICS_GENERATION >= 8
    elsif target.damageState.iceFace
      @battle.pbShowAbilitySplash(target)
      if !Battle::Scene::USE_ABILITY_SPLASH
        @battle.pbDisplay(_INTL("{1}'s {2} activated!", target.pbThis, target.abilityName))
      end
      target.pbChangeForm(1, _INTL("{1} transformed!", target.pbThis))
      @battle.pbHideAbilitySplash(target)
    elsif target.damageState.endured
      @battle.pbDisplay(_INTL("{1} endured the hit!", target.pbThis))
    elsif target.damageState.sturdy
      @battle.pbShowAbilitySplash(target)
      if Battle::Scene::USE_ABILITY_SPLASH
        @battle.pbDisplay(_INTL("{1} endured the hit!", target.pbThis))
      else
        @battle.pbDisplay(_INTL("{1} hung on with Sturdy!", target.pbThis))
      end
      @battle.pbHideAbilitySplash(target)
    elsif target.damageState.focusSash
      @battle.pbCommonAnimation("UseItem", target)
      @battle.pbDisplay(_INTL("{1} hung on using its Focus Sash!", target.pbThis))
      target.pbConsumeItem
    elsif target.damageState.focusBand
      @battle.pbCommonAnimation("UseItem", target)
      @battle.pbDisplay(_INTL("{1} hung on using its Focus Band!", target.pbThis))
    elsif target.damageState.affection_endured
      @battle.pbDisplay(_INTL("{1} toughed it out so you wouldn't feel sad!", target.pbThis))
    end
  end
end