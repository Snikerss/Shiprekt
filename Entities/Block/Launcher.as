#include "WaterEffects.as"
#include "BlockCommon.as"
#include "IslandsCommon.as"
#include "Booty.as"
#include "AccurateSoundPlay.as"
 
const f32 BULLET_SPEED = 3.0f;
const f32 BULLET_RANGE = 240.0f;

const f32 MIN_FIRE_PAUSE = 2.75f;	//used for animations only

const int MIN_TICKS_PER_SHOT = 20;
const int RELOAD_TICKS = 400;
const u8 MAX_AMMO = 2; //maximum carryable ammunition

void onInit( CBlob@ this )
{
	this.getCurrentScript().tickFrequency = 2;

	this.Tag("weapon");
	this.Tag("usesAmmo");
	this.Tag("machinegun");
	
	this.addCommandID("fire");
	this.addCommandID("disable");
	
	this.set_bool( "mShipDocked", false );
	
	if ( getNet().isServer() )
	{	
		this.set_u16( "ammo", MAX_AMMO );
		this.set_u16( "maxAmmo", MAX_AMMO );
		this.set_bool( "mShipDocked", false );
		this.set_u32("fire time", 0);
		this.set_u32("reload time", 0);
		this.set_bool( "reloading", false );
		
		this.Sync("ammo", true );
		this.Sync("maxAmmo", true );
		this.Sync("fire time", true );
		this.Sync("reload time", true );
		this.Sync( "reloading", true );
	}
   
	CSprite@ sprite = this.getSprite();
    CSpriteLayer@ layer = sprite.addSpriteLayer( "weapon", 16, 16 );
    if (layer !is null)
    {
        layer.SetRelativeZ(2);
        layer.SetLighting( false );
        Animation@ anim = layer.addAnimation( "fire", Maths::Round( MIN_FIRE_PAUSE ), false );
        anim.AddFrame(Block::LAUNCHER3);
        anim.AddFrame(Block::LAUNCHER1);
               
		Animation@ anim3 = layer.addAnimation( "default", 1, false );
		anim3.AddFrame(Block::LAUNCHER1);
        layer.SetAnimation("default");  
    }
}
 
void onTick( CBlob@ this )
{
	if ( this.getShape().getVars().customData <= 0 )//not placed yet
		return;
	
	u32 gameTime = getGameTime();
	Vec2f pos = this.getPosition();
	
	CSprite@ sprite = this.getSprite();
	
	u32 fireTime = this.get_u32("fire time");
	this.set_bool( "fire ready", canShoot(this) );
	
	bool isReloading = this.get_bool( "reloading" );
	u32 reloadTime = this.get_u32( "reload time" );
	if ( isReloading )
	{
		//update reloading progress
		CSpriteLayer@ progressBar = sprite.getSpriteLayer( "progress bar" );
		if (progressBar !is null)
		{				
			f32 barScale = (1.0f-(1.0f*(gameTime-reloadTime)/(1.0f*RELOAD_TICKS)));						
			progressBar.ResetTransform();						
			progressBar.ScaleBy( Vec2f(barScale, 1.0f) );				
			progressBar.TranslateBy( Vec2f(-4.0f*(1.0f-barScale), 4.0f) );
		}
		
		if ( (reloadTime + RELOAD_TICKS) < gameTime )
		{
			//reload ammo
			this.set_u16( "ammo", MAX_AMMO );
			this.Sync( "ammo", true );

			this.set_bool( "reloading", false );
			this.Sync( "reloading", true );
			
			directionalSoundPlay( "ReloadEnd", pos, 2.0f );
			
			sprite.RemoveSpriteLayer("black bar");
			sprite.RemoveSpriteLayer("progress bar");
		}
	}
	
	//reload if out of ammo
	if ( !isReloading && this.get_u16( "ammo" ) <= 0  )
	{		
		this.set_bool( "reloading", true );
		this.set_u32("reload time", getGameTime());
		
		directionalSoundPlay( "ReloadStart", pos, 2.0f );
		
		if ( getNet().isClient() ) //reload bar
		{
			sprite.RemoveSpriteLayer("black bar");
			CSpriteLayer@ blackBar = sprite.addSpriteLayer("black bar", "reload_bar.png", 8, 2);
			if (blackBar !is null)
			{
				blackBar.SetRelativeZ(4);
				blackBar.SetFrame(0);
				blackBar.SetVisible(true);						
				blackBar.ResetTransform();												
				blackBar.TranslateBy( Vec2f(0.0f, 4.0f) );	
			}
			sprite.RemoveSpriteLayer("progress bar");
			CSpriteLayer@ progressBar = sprite.addSpriteLayer("progress bar", "reload_bar.png", 8, 2);
			if (progressBar !is null)
			{
				progressBar.SetRelativeZ(5);
				progressBar.SetFrame(1);
				progressBar.SetVisible(true);					
				progressBar.ResetTransform();										
				progressBar.TranslateBy( Vec2f(0.0f, 4.0f) );
			}
		}
	}
}
 
bool canShoot( CBlob@ this )
{
	return ( this.get_u32("fire time") + MIN_TICKS_PER_SHOT < getGameTime() );
}

bool isClear( CBlob@ this )
{
	Vec2f pos = this.getPosition();
	Vec2f aimVector = Vec2f(1, 0).RotateBy(this.getAngleDegrees());
	u8 teamNum = this.getTeamNum();
	bool clear = true;
	
	HitInfo@[] hitInfos;
	if( getMap().getHitInfosFromRay( pos, -aimVector.Angle(), BULLET_RANGE/4, this, @hitInfos ) )
		for ( uint i = 0; i < hitInfos.length; i++ )
		{
			CBlob@ b =  hitInfos[i].blob;	  
			if( b is null || b is this ) continue;

			if ( b.hasTag("weapon") && b.getTeamNum() == teamNum )//team weaps
			{
				clear = false;
				break;
			}
		}
		
	return clear;
}
 
void onCommand( CBlob@ this, u8 cmd, CBitStream @params )
{
    if (cmd == this.getCommandID("fire"))
    {
		if ( !canShoot(this) )
			return;
		
		u16 shooterID;
		if ( !params.saferead_u16(shooterID) )
			return;
		
		CBlob@ shooter = getBlobByNetworkID( shooterID );
		if (shooter is null)
			return;

		bool isServer = getNet().isServer();
		Vec2f pos = this.getPosition();
		
		if ( !isClear( this ) )
		{
			directionalSoundPlay( "lightup", pos );
			return;
		}
		
		bool isReloading = this.get_bool( "reloading" );
		
		//ammo
		u16 ammo = this.get_u16( "ammo" );
		
		if ( ammo <= 0 )
		{
			directionalSoundPlay( "LoadingTick1", pos, 0.5f );	
			return;
		}
		
		ammo--;
		this.set_u16( "ammo", ammo );
		
		Island@ island = getIsland( this.getShape().getVars().customData );
		if ( island is null )
			return;
			
		//autocannon effects
		CSprite@ sprite = this.getSprite();
		CSpriteLayer@ layer = sprite.getSpriteLayer( "weapon" );
		layer.SetAnimation( "default" );
	   
		Vec2f aimvector = Vec2f(1, 0).RotateBy(this.getAngleDegrees());
			
		Vec2f barrelPos = this.getPosition() + aimvector*9;

		//hit stuff
		u8 teamNum = shooter.getTeamNum();//teamNum of the player firing
		HitInfo@[] hitInfos;
		CMap@ map = this.getMap();
			
		Vec2f velocity = aimvector*BULLET_SPEED;
		
		if (isServer)
		{
            CBlob@ bullet = server_CreateBlob( "rocket", this.getTeamNum(), pos + aimvector*8.0f );
            if (bullet !is null)
            {
            	if (shooter !is null){
                	bullet.SetDamageOwnerPlayer( shooter.getPlayer() );
                }
                bullet.setVelocity( velocity + ((getIsland(this) !is null) ? getIsland( this ).vel : Vec2f(0, 0)) );
				bullet.setAngleDegrees(-aimvector.Angle() + 90.0f);
            }
    	}		
		
		shotParticles( barrelPos, aimvector.Angle() );
		directionalSoundPlay( "LauncherFire" + ( XORRandom(2) + 1 ) + ".ogg", barrelPos );
		layer.SetAnimation( "fire" );	
		
		this.set_u32( "fire time", getGameTime());
    }
}
 
Random _shotrandom(0x15125); //clientside
void shotParticles(Vec2f pos, float angle )
{
	//muzzle flash
	CParticle@ p = ParticleAnimated( "Entities/Block/turret_muzzle_flash.png",
																					  pos, Vec2f(),
																					  -angle, //angle
																					  1.0f, //scale
																					  3, //animtime
																					  0.0f, //gravity
																					  true ); //selflit
	if(p !is null)
			p.Z = 10.0f;
}

Random _sprk_r;
void sparks(Vec2f pos, int amount)
{
	for (int i = 0; i < amount; i++)
    {
        Vec2f vel(_sprk_r.NextFloat() * 1.0f, 0);
        vel.RotateBy(_sprk_r.NextFloat() * 360.0f);

        CParticle@ p = ParticlePixel( pos, vel, SColor( 255, 255, 128+_sprk_r.NextRanged(128), _sprk_r.NextRanged(128)), true );
        if(p is null) return; //bail if we stop getting particles

        p.timeout = 10 + _sprk_r.NextRanged(20);
        p.scale = 0.5f + _sprk_r.NextFloat();
        p.damping = 0.95f;
    }
}

void damageBooty( CPlayer@ attacker, CBlob@ attackerBlob, CBlob@ victim )
{
	if ( victim.getName() == "block" )
	{
		const int blockType = victim.getSprite().getFrame();
		u8 teamNum = attacker.getTeamNum();
		u8 victimTeamNum = victim.getTeamNum();
		string attackerName = attacker.getUsername();
		Island@ victimIsle = getIsland( victim.getShape().getVars().customData );
		
		if ( victimIsle !is null
			&& ( victimIsle.owner != "" || victimIsle.isMothership )
			&& victimTeamNum != teamNum
			&& ( blockType == Block::PROPELLER || victim.hasTag("weapon") || Block::isBomb( blockType ) || blockType == Block::SEAT || blockType == Block::RAMCHAIR )
			)
		{
			if ( attacker.isMyPlayer() )
			{
				u8 n = XORRandom(4);
				if ( n == 3 )
					Sound::Play( "Pinball_" + XORRandom(4), attackerBlob.getPosition(), 0.5f );
				else
					Sound::Play( "Pinball_" + n, attackerBlob.getPosition(), 0.5f );					
			}

			if ( getNet().isServer() )
			{
				CRules@ rules = getRules();
			
				u16 reward = 4;//propellers, seat
				if ( victim.hasTag( "weapon" ) || Block::isBomb( blockType ) )
					reward += 2;
								
				f32 bFactor = ( rules.get_bool( "whirlpool" ) ? 3.0f : 1.0f ) * Maths::Min( 2.5f, Maths::Max( 0.15f,
				( 2.0f * rules.get_u16( "bootyTeam_total" + victimTeamNum ) - rules.get_u16( "bootyTeam_total" + teamNum ) + 1000 )/( rules.get_u32( "bootyTeam_median" ) + 1000 ) ) );
				
				reward = Maths::Round( reward * bFactor );
				
				server_setPlayerBooty( attackerName, server_getPlayerBooty( attackerName ) + reward );
				server_updateTotalBooty( teamNum, reward );
			}
		}
	}
}