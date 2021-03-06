// thanks to Splittingred
#define CLIENT_ONLY
#include "HoverMessage.as";
#include "ActorHUDStartPos.as"
int oldBooty = 0;

void onTick( CSprite@ this )
{
	CBlob@ blob = this.getBlob();
	CPlayer@ player = blob.getPlayer();
	CRules@ rules = getRules();
	
	if ( player is null || !player.isMyPlayer() ) return;
	
	string userName = player.getUsername();
	u16 currentBooty = rules.get_u16( "booty" + userName );
	int diff = currentBooty - oldBooty;
	oldBooty = currentBooty;

	if ( diff > 0 )
		bootyIncrease( blob, diff );//set message
	else if ( diff < 0 )
		bootyDecrease( blob, diff );//set message
	
    HoverMessage2[]@ messages;
    if (blob.get("messages",@messages))
	{
        for (uint i = 0; i < messages.length; i++)
		{
            HoverMessage2 @message = messages[i];
            message.draw( getActorHUDStartPosition(blob, 6) +  Vec2f( 150 , -4) );

            if (message.isExpired()) 
			{
                messages.removeAt(i);
            }
        }
    }
}

void onRender( CSprite@ this )
{
	CBlob@ blob = this.getBlob();

	HoverMessage2[]@ messages;	
	if (blob.get("messages",@messages))
	{
		for (uint i = 0; i < messages.length; i++)
		{
			HoverMessage2 @message = messages[i];
			message.draw( getActorHUDStartPosition(blob, 6) + Vec2f( 150 , -4) + Vec2f( 0, -1)*message.ticksSinceCreated() );
			
			if (message.isExpired()) 
			{
                messages.removeAt(i);
            }
		}
	}
}

void bootyIncrease(CBlob@ this, int ammount )
{
	if (this.isMyPlayer())
	{
		if (!this.exists("messages")) 
		{
			HoverMessage2[] messages;
			this.set( "messages", messages);
		}

		//this.clear( "messages" );
		HoverMessage2 m( "", ammount, SColor(255,0,255,0), 150, 2, false, "+" );
		this.push("messages",m);
	}
}

void bootyDecrease(CBlob@ this, int ammount )
{
	if (this.isMyPlayer())
	{
		if (!this.exists("messages")) 
		{
			HoverMessage2[] messages;
			this.set( "messages", messages);
		}

		//this.clear( "messages" );
		HoverMessage2 m( "", ammount, SColor(255,255,0,0), 150, 2 );
		this.push("messages",m);
	}
}