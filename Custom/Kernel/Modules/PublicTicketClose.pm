# --
# Copyright (C) 2023 mo-azfar, https://github.com/mo-azfar
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
#
# URL - https://app.wsl.my/znuny-devel/public.pl?Action=PublicTicketClose;SessionID=<GENERATED_SESSION_ID>;TicketNumber=<OTRS_TICKET_TicketNumber>
# --

package Kernel::Modules::PublicTicketClose;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
	my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
	
    my %GetParam;
    for my $Needed ( qw( SessionID TicketNumber ) )
	{
        $GetParam{$Needed} = $ParamObject->GetParam( Param => $Needed );
        
        if ( !$GetParam{$Needed} ) {
            return $LayoutObject->CustomerNoPermission( WithHeader => 'yes' );
        }
	}

    #validate session 
    #make sure use from generated one with valid ticket number.
    #also check user access
    my %SessionCheck = $Self->_SessionCheck(
		SessionID  => $GetParam{SessionID},
        TicketNumber => $GetParam{TicketNumber},
    );

    if ( $SessionCheck{Status} eq 'Error' )
    {
        #return $LayoutObject->CustomerNoPermission( WithHeader => 'yes' );
        $LayoutObject->Block(
			Name => 'Error',
			Data => {
			    Message => $SessionCheck{Message},
			},
		);
    }

    else
    {
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

        my %Ticket = $TicketObject->TicketGet(
            TicketID      => $SessionCheck{TicketID},
            DynamicFields => 0,
        );

        if ( $Ticket{State} =~ /^close/i )
        {
            $LayoutObject->Block(
                Name => 'Closed',
                Data => {
                    TicketNumber => $SessionCheck{TicketNumber},
                },
            );
        }
        else 
        {
            my $Success = $TicketObject->TicketStateSet(
                State    => 'closed successful',
                TicketID => $SessionCheck{TicketID},
                UserID    => $ConfigObject->Get('CustomerPanelUserID'),
            );
            
            if ( !$Success )
            {
                my $Output = $LayoutObject->CustomerHeader(
                    Title => Translatable('Error'),
                );
                $Output .= $LayoutObject->CustomerError(
                    Message => Translatable("Unfortunately,  Ticket#$SessionCheck{TicketNumber} can't be close."),
                );
                $Output .= $LayoutObject->CustomerFooter();
                return $Output;		
            }
            
            # set unlock on close state
            $TicketObject->TicketLockSet(
                TicketID => $SessionCheck{TicketID},
                Lock     => 'unlock',
                UserID   => $ConfigObject->Get('CustomerPanelUserID'),
            );
            
            my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');
            my $ArticleBackendObject = $ArticleObject->BackendForChannel( ChannelName => 'Internal' );
            my $ArticleID = $ArticleBackendObject->ArticleCreate(
                TicketID             => $SessionCheck{TicketID},                              
                SenderType           => 'customer',                         
                IsVisibleForCustomer => 1,                               
                UserID               => $ConfigObject->Get('CustomerPanelUserID'), 
                From           =>  $SessionCheck{From},       
                Subject        => $Ticket{Title},               
                Body           => 'Auto generated noted.<br/>Ticket now closed by customer.',                     
                ContentType    => 'text/html; charset=UTF-8',      
                HistoryType    => 'FollowUp',                        
                HistoryComment => 'Added follow-up from CustomerTicketClose to ticket',
                NoAgentNotify    => 0,                                      # if you don't want to send agent notifications
            );

            $LayoutObject->Block(
                Name => 'Closing',
                Data => {
                    TicketNumber => $SessionCheck{TicketNumber},
                },
            );
            
        }

        my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
	    # destroy generated session
	    $SessionObject->RemoveSessionID(SessionID => $GetParam{SessionID});

    }
    
   	# generate output
    my $Output = $LayoutObject->CustomerHeader( Value => 'Close Ticket' );
	
	$Output  .= $LayoutObject->Output(
        TemplateFile => 'PublicTicketClose',
		Data         => { 
			%Param, 
		},
    );
	
    $Output   .= $LayoutObject->CustomerFooter();
	
	return $Output;
	  
}

sub _SessionCheck {
    my ( $Self, %Param ) = @_;

    my %SessionValidate;

	my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
	my %SessionData = $SessionObject->GetSessionIDData(
        SessionID => $Param{SessionID},
    );

    #Invalid Session Data!
    if ( $SessionData{SessionSource} ne 'GenericInterface' )
	{
        $SessionValidate{Status} = 'Error';
        $SessionValidate{Message} = 'Unfortunately, This Session No Longer Valid';
		return %SessionValidate;
	}
	
    #Invalid Ticket Number in URL
    if ( $SessionData{TicketNumber} ne $Param{TicketNumber} )
	{
        $SessionValidate{Status} = 'Error';
        $SessionValidate{Message} = 'Invalid Ticket Number';
		return %SessionValidate;
	}

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    #search for ticket id
    my $TicketID = $TicketObject->TicketIDLookup( 
        TicketNumber => $SessionData{TicketNumber},
        UserID       => $SessionData{UserID},
    );

    if ( !$TicketID )
    {
        $SessionValidate{Status} = 'Error';
        $SessionValidate{Message} = 'Ticket Not Found';
		return %SessionValidate;
    }

    # check access permissions
    my $Access = $TicketObject->TicketCustomerPermission(
        Type     => 'ro',
        TicketID => $TicketID,
        UserID   => $SessionData{UserID},
    );

    if ( !$Access )
    {
        $SessionValidate{Status} = 'Error';
        $SessionValidate{Message} = 'You have no permission';
		return %SessionValidate;
    }

    $SessionValidate{Status} = 'OK';
    $SessionValidate{TicketID} = $TicketID;
    $SessionValidate{TicketNumber} = $SessionData{TicketNumber};
    $SessionValidate{From} = "\"$SessionData{UserFullname}\" <$SessionData{UserEmail}>";
   
    return %SessionValidate;
}

1;