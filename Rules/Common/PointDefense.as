#include "BlockCommon.as"
#include "IslandsCommon.as"
#include "AccurateSoundPlay.as"

const f32 PROJECTILE_SPEED = 9.0f;
const f32 PROJECTILE_SPREAD = 2.25;
const f32 PROJECTILE_RANGE = 100.0f;

const int MIN_TICKS_PER_SHOT = 40;
const int RELOAD_TICKS = 120;
const u8 MAX_AMMO = 6; //maximum carryable ammunition

const f32 AUTO_RADIUS = 100.0f;

Random _shotspreadrandom(0x11598); //clientside

void onInit( CBlob@ this )
{
	this.Tag("pointDefense");
	this.Tag("weapon");
	this.Tag("usesAmmo");
	
	this.addCommandID("fire");
	this.addCommandID("clear attached");
	
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
     	Animation@ anim = layer.addAnimation( "fire", 15, false );
        anim.AddFrame(Block::POINTDEFENSE_A2);
        anim.AddFrame(Block::POINTDEFENSE_A1);
        layer.SetAnimation("fire");    	
    }
}

void onTick( CBlob@ this )
{
	if ( this.getShape().getVars().customData <= 0 )
		return;
	
	u32 gameTime = getGameTime();
	Vec2f pos = this.getPosition();
	
	AttachmentPoint@ seat = this.getAttachmentPoint(0);
	CBlob@ occupier = seat.getOccupied();
	u16 thisID = this.getNetworkID();
	
	CSprite@ sprite = this.getSprite();
    CSpriteLayer@ laser = sprite.getSpriteLayer( "laser" );
	if ( laser !is null && this.get_u32("fire time") + 5.0f < gameTime )
		sprite.RemoveSpriteLayer("laser");
	
	bool isReloading = this.get_bool( "reloading" );
	if ( !isReloading )
	{
		Auto( this );
	}
	
	//reloading
	u32 reloadTime = this.get_u32( "reload time" );
	if ( isReloading )
	{
		//conditional reload time based on whether or not in manual mode
		int reloadTicks = RELOAD_TICKS;
		if (occupier !is null)
			reloadTicks = RELOAD_TICKS/4;
		
		//update reloading progress
		CSpriteLayer@ progressBar = sprite.getSpriteLayer( "progress bar" );
		if (progressBar !is null)
		{				
			f32 barScale = (1.0f-(1.0f*(gameTime-reloadTime)/(1.0f*reloadTicks)));						
			progressBar.ResetTransform();						
			progressBar.ScaleBy( Vec2f(barScale, 1.0f) );				
			progressBar.TranslateBy( Vec2f(-4.0f*(1.0f-barScale), 4.0f) );
		}
		
		if ( (reloadTime + reloadTicks) < gameTime )
		{
			//reload ammo
			this.set_u16( "ammo", MAX_AMMO );
			this.Sync( "ammo", true );

			this.set_bool( "reloading", false );
			this.Sync( "reloading", true );
			
			directionalSoundPlay( "ReloadEnd", this.getPosition(), 2.0f );
			
			sprite.RemoveSpriteLayer("black bar");
			sprite.RemoveSpriteLayer("progress bar");
		}
	}
	
	//reload it out of ammo
	if ( !isReloading && this.get_u16( "ammo" ) <= 0  )
	{		
		this.set_bool( "reloading", true );
		this.set_u32("reload time", getGameTime());
		
		directionalSoundPlay( "ReloadStart", pos, 2.0f );
		
		if ( getNet().isClient() ) //reload bar
		{
			CSprite@ sprite = this.getSprite();
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

void Auto( CBlob@ this )
{
	if ( ( getGameTime() + this.getNetworkID() * 33 ) % 5 != 0 )
		return;
		
	CBlob@[] blobsInRadius;
	Vec2f pos = this.getPosition();
	int thisColor = this.getShape().getVars().customData;
	f32 minDistance = 9999999.9f;
	bool shoot = false;
	Vec2f shootVec = Vec2f(0, 0);
	
	u16 hitBlobNetID = 0;
	Vec2f bPos = Vec2f(0, 0);

	if ( this.getMap().getBlobsInRadius( this.getPosition(), AUTO_RADIUS, @blobsInRadius ) )
	{
		for ( uint i = 0; i < blobsInRadius.length; i++ )
		{
			CBlob @b = blobsInRadius[i];
			if ( b.getTeamNum() != this.getTeamNum() 
					&& ( b.getName() == "human"|| b.hasTag( "rocket" ) ||  b.hasTag( "cannonball" ) || b.hasTag( "bullet" ) || b.hasTag( "flak shell" ) ) )
			{
				bPos = b.getPosition();
				
				Island@ targetIsland;
				if ( b.getName() == "block" )
					@targetIsland = getIsland( b.getShape().getVars().customData );
				else
				{
					@targetIsland = getIsland(b);
					if ( b.isAttached() )
					{
						AttachmentPoint@ humanAttach = b.getAttachmentPoint(0);
						CBlob@ seat = humanAttach.getOccupied();
						if ( seat !is null )
							bPos = seat.getPosition();
					}
				}
				
				Vec2f aimVec = bPos - pos;
				f32 distance = aimVec.Length();

				int bColor = 0;
				
				bool merged = bColor != 0 && thisColor == bColor;
				
				if ( b.getName() == "human" )
					distance += 80.0f;//humans have lower priority
				
				if ( distance < minDistance && isClearShot( this, aimVec, merged ) )
				{
					shoot = true;					
					shootVec = aimVec;
					minDistance = distance;
					hitBlobNetID = b.getNetworkID();
				}
			}
		}
	}
	
	if ( shoot )
	{	
		if ( getNet().isServer() && canShootAuto( this ) )
		{		
			Fire( this, shootVec, hitBlobNetID );
		}
	}
}

bool canShootAuto( CBlob@ this, bool manual = false )
{
	return this.get_u32("fire time") + MIN_TICKS_PER_SHOT < getGameTime();
}

bool isClearShot( CBlob@ this, Vec2f aimVec, bool targetMerged = false )
{
	Vec2f pos = this.getPosition();
	const f32 distanceToTarget = Maths::Max( aimVec.Length() - 8.0f, 0.0f );
	HitInfo@[] hitInfos;
	CMap@ map = getMap();
	
	Vec2f offset = aimVec;
	offset.Normalize();
	offset *= 7.0f;

	map.getHitInfosFromRay( pos + offset.RotateBy(30), -aimVec.Angle(), distanceToTarget, this, @hitInfos );
	map.getHitInfosFromRay( pos + offset.RotateBy(-60), -aimVec.Angle(), distanceToTarget, this, @hitInfos );
	if ( hitInfos.length > 0 )
	{
		//HitInfo objects are sorted, first come closest hits
		for ( uint i = 0; i < hitInfos.length; i++ )
		{
			HitInfo@ hi = hitInfos[i];
			CBlob@ b = hi.blob;	  
			if( b is null || b is this ) continue;

			int thisColor = this.getShape().getVars().customData;
			int bColor = b.getShape().getVars().customData;
			bool sameIsland = bColor != 0 && thisColor == bColor;
			
			const int blockType = b.getSprite().getFrame();

			bool canShootSelf = targetMerged && hi.distance > distanceToTarget * 0.7f;
			
			bool isOwnCore = Block::isCore( blockType ) && this.getTeamNum() == b.getTeamNum();
		
			//if ( sameIsland || targetMerged ) print ( "" + ( sameIsland ? "sameisland; " : "" ) + ( targetMerged ? "targetMerged; " : "" ) );
			
			if ( b.hasTag("weapon") || Block::isSolid( blockType )
					|| ( b.getName() == "block" && b.getShape().getVars().customData > 0 && ( Block::isSolid( blockType ) ) && !canShootSelf ) )
			{
				//print ( "not clear " + ( b.getName() == "block" ? " (block) " : "" ) + ( !canShootSelf ? "!canShootSelf; " : "" )  );
				return false;
			}
		}
	}
	
	Vec2f solidPos;
	if ( map.rayCastSolid(pos, pos + aimVec, solidPos) )
	{
			return false;
	}

	return true;
}

void Fire( CBlob@ this, Vec2f aimVector, const u16 hitBlobNetID )
{
	CBitStream params;
	params.write_netid( hitBlobNetID );
	params.write_Vec2f( aimVector );
	
	this.SendCommand( this.getCommandID("fire"), params );
	
	this.set_u32("fire time", getGameTime());
	this.Sync("fire time", true );
}

void Rotate( CBlob@ this, Vec2f aimVector )
{
	CSpriteLayer@ layer = this.getSprite().getSpriteLayer("weapon");
	if(layer !is null)
	{
		layer.ResetTransform();
		layer.RotateBy( -aimVector.getAngleDegrees() - this.getAngleDegrees(), Vec2f_zero );
	}
}

void onCommand( CBlob@ this, u8 cmd, CBitStream @params )
{
    if (cmd == this.getCommandID("fire"))
    {
		CBlob@ hitBlob = getBlobByNetworkID( params.read_netid() );
		Vec2f aimVector = params.read_Vec2f();
		
		if (hitBlob is null)
			return;
		
		Vec2f pos = this.getPosition();		
		Vec2f bPos = hitBlob.getPosition();
		bool isServer = getNet().isServer();
		
		//ammo
		u16 ammo = this.get_u16( "ammo" );
		
		if ( ammo <= 0 )
		{
			directionalSoundPlay( "LoadingTick1", pos, 1.0f );
			return;
		}
		
		ammo--;
		this.set_u16( "ammo", ammo );
		if ( isServer )
			this.set( "ammo", ammo );
		
		if (hitBlob !is null)
		{		
			if ( isServer )
			{
				f32 damage = getDamage( hitBlob );
				this.server_Hit( hitBlob, bPos, Vec2f_zero, damage, 0, true );
			}
			hitBlob.Tag( "disarmed" );
			
			Rotate( this, aimVector ); 
			shotParticles(pos + aimVector*9, aimVector.Angle());
			directionalSoundPlay( "Laser1.ogg", pos, 1.0f );
			
			Vec2f barrelPos = pos + Vec2f(1,0).RotateBy(aimVector.Angle())*8;
			if ( getNet().isClient() )//effects
			{	
				CSprite@ sprite = this.getSprite();
				sprite.RemoveSpriteLayer("laser");
				CSpriteLayer@ laser = sprite.addSpriteLayer("laser", "Beam2.png", 16, 16);
				if (laser !is null)//partial length laser
				{
					Animation@ anim = laser.addAnimation( "default", 1, false );
					int[] frames = { 0, 1, 2, 3, 4, 5 };
					anim.AddFrames(frames);
					laser.SetVisible(true);
					f32 laserLength = Maths::Max(0.1f, (bPos - barrelPos).getLength() / 16.0f);						
					laser.ResetTransform();						
					laser.ScaleBy( Vec2f(laserLength, 0.5f) );							
					laser.TranslateBy( Vec2f(laserLength*8.0f, 0.0f) );							
					laser.RotateBy( -this.getAngleDegrees() - aimVector.Angle(), Vec2f());
					laser.setRenderStyle(RenderStyle::light);
					laser.SetRelativeZ(1);
				}

				hitEffects( hitBlob, bPos );
			}
		}
		
		CSpriteLayer@ layer = this.getSprite().getSpriteLayer( "weapon" );
		if ( layer !is null )
			layer.animation.SetFrameIndex(0);
    }
}

f32 getDamage( CBlob@ hitBlob )
{	
	if ( hitBlob.hasTag( "rocket" ) )
		return 1.0f;

	if ( hitBlob.hasTag( "cannonball" ) )
		return 1.0f;
		
	if ( hitBlob.hasTag( "bullet" ) )
		return 1.0f;
	
	if ( hitBlob.hasTag( "flak shell" ) )
		return 1.0f;
		
	if ( hitBlob.getName() == "human" )
		return 0.05f;
	
	return 0.01f;//cores, solids
}

Random _shotrandom(0x15125); //clientside
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
}

void hitEffects( CBlob@ hitBlob, Vec2f worldPoint )
{
	if (hitBlob.hasTag("player") )
	{
		directionalSoundPlay( "ImpactFlesh", worldPoint );
		ParticleBloodSplat( worldPoint, true );
	}
	else if ( hitBlob.hasTag("projectile") )
	{
		sparks(worldPoint, 4);
	}
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