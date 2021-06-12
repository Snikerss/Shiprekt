#include "BlockCommon.as"
#include "IslandsCommon.as"
#include "AccurateSoundPlay.as"
 
const f32 PROJECTILE_RANGE = 375.0F;
const f32 PROJECTILE_SPEED = 15.0f;;

const int MIN_TICKS_PER_SHOT = 80;
const int RELOAD_TICKS = 160;
const u8 MAX_AMMO = 4; //maximum carryable ammunition

Random _shotrandom(0x15125); //clientside

void onInit( CBlob@ this )
{
	this.Tag("weapon");
	this.Tag("cannon");
	this.Tag("usesAmmo");
	this.Tag("fixed_gun");
	
	this.addCommandID("fire");
	
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
     	Animation@ anim = layer.addAnimation( "fire", 0, false );
        anim.AddFrame(Block::CANNON_A1);
        anim.AddFrame(Block::CANNON_A2);
        layer.SetAnimation("fire");
    }
}

void onTick( CBlob@ this )
{
	if (this.getShape().getVars().customData <= 0)
		return;
	
	u32 gameTime = getGameTime();
	Vec2f pos = this.getPosition();
	
	CSprite@ sprite = this.getSprite();
	
	//fire ready
	u32 fireTime = this.get_u32("fire time");
	this.set_bool( "fire ready", canShoot(this) );
	
	//sprite ready
	if ( fireTime + MIN_TICKS_PER_SHOT - 15 == gameTime )
	{
		CSpriteLayer@ layer = this.getSprite().getSpriteLayer( "weapon" );
		if ( layer !is null )
			layer.animation.SetFrameIndex(0);

		directionalSoundPlay( "Charging.ogg", this.getPosition(), 2.0f );
	}
	
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
			directionalSoundPlay( "LoadingTick1", pos, 1.0f );
			return;
		}
		
		ammo--;
		this.set_u16( "ammo", ammo );

		Fire( this, shooter );
	
		CSpriteLayer@ layer = this.getSprite().getSpriteLayer( "weapon" );
		if ( layer !is null )
			layer.animation.SetFrameIndex(1);
			
		this.set_u32( "fire time", getGameTime() );
    }
}

void Fire( CBlob@ this, CBlob@ shooter )
{
	Vec2f pos = this.getPosition();
	Vec2f aimVector = Vec2f(1, 0).RotateBy(this.getAngleDegrees());

	if ( getNet().isServer() )
	{
		f32 variation = 0.9f + _shotrandom.NextFloat()/5.0f;
		f32 _lifetime = 0.05f + variation*PROJECTILE_RANGE/PROJECTILE_SPEED/32.0f;

		CBlob@ cannonball = server_CreateBlob( "cannonball", this.getTeamNum(), pos + aimVector*4 );
		if ( cannonball !is null )
		{
			Vec2f vel = aimVector * PROJECTILE_SPEED;
			
			Island@ isle = getIsland( this.getShape().getVars().customData );
			if ( isle !is null )
			{
				vel += isle.vel;
				
				if ( shooter !is null )
				{
					CPlayer@ attacker = shooter.getPlayer();
					if ( attacker !is null )
						cannonball.SetDamageOwnerPlayer( attacker );
				}

				cannonball.setVelocity( vel );
				cannonball.server_SetTimeToDie( _lifetime );
			}
		}
	}
	
	CSpriteLayer@ layer = this.getSprite().getSpriteLayer( "weapon" );
	if ( layer !is null )
		layer.animation.SetFrameIndex(0);

	shotParticles(pos + aimVector*9, aimVector.Angle());
	
	directionalSoundPlay( "CannonFire.ogg", pos, 7.0f );
		
	this.set_bool( "firing", false );
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
	if( getMap().getHitInfosFromRay( pos, -aimVector.Angle(), PROJECTILE_RANGE/4, this, @hitInfos ) )
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

void shotParticles(Vec2f pos, float angle)
{
	//muzzle flash
	{
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

	Vec2f shot_vel = Vec2f(0.5f,0);
	shot_vel.RotateBy(-angle);

	//smoke
	for(int i = 0; i < 5; i++)
	{
		//random velocity direction
		Vec2f vel(0.1f + _shotrandom.NextFloat()*0.2f, 0);
		vel.RotateBy(_shotrandom.NextFloat() * 360.0f);
		vel += shot_vel * i;

		CParticle@ p = ParticleAnimated( "Entities/Block/turret_smoke.png",
												  pos, vel,
												  _shotrandom.NextFloat() * 360.0f, //angle
												  1.0f, //scale
												  3+_shotrandom.NextRanged(4), //animtime
												  0.0f, //gravity
												  true ); //selflit
		if(p !is null)
			p.Z = 550.0f;
	}
}