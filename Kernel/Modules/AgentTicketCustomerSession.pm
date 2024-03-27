# --
# Copyright (C) 2022-2024 mo-azfar, https://github.com/mo-azfar
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::AgentTicketCustomerSession;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::AuthSession',
    'Kernel::System::CustomerUser',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Ticket',
);

use Kernel::Language qw(Translatable);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    if ( !$Self->{TicketID} ) {
        return $LayoutObject->ErrorScreen(
            Message => 'No TicketID is given!',
            Comment => 'Please contact the admin.',
        );
    }

    my $AccessOk = $TicketObject->OwnerCheck(
        TicketID => $Self->{TicketID},
        OwnerID  => $Self->{UserID},
    );

    if ( !$AccessOk )
    {
        return $LayoutObject->ErrorScreen(
            Message => 'Need owner!',
            Comment => 'Please contact the admin.',
        );
    }

    my $ConfigObject              = $Kernel::OM->Get('Kernel::Config');
    my $CustomerUserObject        = $Kernel::OM->Get('Kernel::System::CustomerUser');
    my $SessionObject             = $Kernel::OM->Get('Kernel::System::AuthSession');
    my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $DateTimeObject            = $Kernel::OM->Create('Kernel::System::DateTime');
    my $Epoch                     = $DateTimeObject->ToEpoch();

    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Self->{TicketID},
        DynamicFields => 0,
    );

    #just in case ticket customer change from valid to non valid.
    my %UserData = $CustomerUserObject->CustomerUserDataGet(
        User  => $Ticket{CustomerUserID},
        Valid => 1,
    );

    if ( !$UserData{UserID} )
    {
        return $LayoutObject->ErrorScreen(
            Message => 'Need a valid customer user!',
            Comment => 'Please contact the admin.',
        );
    }

    my $DynamicFieldName = $ConfigObject->Get('Ticket::Frontend::AgentTicketCustomerSession')->{'DynamicField'};

    if ( !$DynamicFieldName )
    {
        return $LayoutObject->ErrorScreen(
            Message => 'Ticket::Frontend::AgentTicketCustomerSession###DynamicField is not set',
            Comment => 'Please contact the admin.',
        );
    }

    my $DynamicFieldCustomerSession = $DynamicFieldObject->DynamicFieldGet(
        Name => $DynamicFieldName,
    );

    if ( !%{$DynamicFieldCustomerSession} )
    {
        return $LayoutObject->ErrorScreen(
            Message => 'Ticket::Frontend::AgentTicketCustomerSession###DynamicField is not a valid field',
            Comment => 'Please contact the admin.',
        );
    }

    my $CustomerSessionValue = $DynamicFieldBackendObject->ValueGet(
        DynamicFieldConfig => $DynamicFieldCustomerSession,
        ObjectID           => $Self->{TicketID},
    );

    if ($CustomerSessionValue)
    {
        #remove existing session id
        $SessionObject->RemoveSessionID( SessionID => $CustomerSessionValue );
    }

    #create new customer session with ticket number
    my $NewSessionID = $SessionObject->CreateSessionID(
        %UserData,
        UserLastRequest => $Epoch,
        UserType        => 'Customer',
        SessionSource   => 'GenericInterface',
        TicketNumber    => $Ticket{TicketNumber},
    );

    my $SetCustomerSessionValue = $DynamicFieldBackendObject->ValueSet(
        DynamicFieldConfig => $DynamicFieldCustomerSession,
        ObjectID           => $Self->{TicketID},
        Value              => $NewSessionID,
        UserID             => $Self->{UserID},
    );

    #return output
    return $LayoutObject->Redirect(
        OP => "Action=AgentTicketZoom;TicketID=$Self->{TicketID}",
    );
}

1;
