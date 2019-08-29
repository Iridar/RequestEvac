class GameState_RequestEvac extends XComGameState_BaseObject config(RequestEvac);

// var config bool DisplayFlareBeforeEvacSpawn;
var config int TurnsBeforeEvacExpires;
var privatewrite int Countdown;
var privatewrite int RemoveEvacCountdown;
var() protectedwrite Vector EvacLocation;
var privatewrite bool SkipCreationNarrative;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////                        LONG WAR                        ///////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

function OnEndTacticalPlay(XComGameState NewGameState)
{
	local X2EventManager EventManager;
	local Object ThisObj;

	ThisObj = self;
	EventManager = `XEVENTMGR;

	EventManager.UnRegisterFromEvent(ThisObj, 'EvacSpawnerCreated');
	EventManager.UnRegisterFromEvent(ThisObj, 'SpawnEvacZoneComplete');
}

// A new evac spawner was created.
function EventListenerReturn OnEvacSpawnerCreated(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState NewGameState;
	local GameState_RequestEvac NewSpawnerState;

	// Set up visualization to drop the flare.
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState(string(GetFuncName()));
	NewSpawnerState = GameState_RequestEvac(NewGameState.ModifyStateObject(class'GameState_RequestEvac', ObjectID));
	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualizationForSpawnerCreation;
	NewGameState.GetContext().SetAssociatedPlayTiming(SPT_AfterSequential);
	`TACTICALRULES.SubmitGameState(NewGameState);

	// no countdown specified, spawn the evac zone immediately. Otherwise we'll tick down each turn start (handled in
	// UIScreenListener_RequestEvac to also display the counter).
	if (Countdown == 0)
	{
		NewSpawnerState.SpawnEvacZone();
	}

	return ELR_NoInterrupt;
}

function SoldierRequestEvac(XComGameState GameState)
{
	local GameState_RequestEvac SpawnerState;
	local VisualizationActionMetadata ActionMetadata;

	SpawnerState = GameState_RequestEvac(`XCOMHISTORY.GetGameStateForObjectID(ObjectID));

	ActionMetadata.StateObject_OldState = SpawnerState;
	ActionMetadata.StateObject_NewState = SpawnerState;
	ActionMetadata.VisualizeActor = SpawnerState.GetVisualizer();

	class'Action_RequestEvac'.static.AddToVisualizationTree(ActionMetadata, GameState.GetContext());
}

// Visualize the spawner creation: drop a flare at the point the evac zone will appear.
function BuildVisualizationForSpawnerCreation(XComGameState VisualizeGameState)
{
	local VisualizationActionMetadata BuildTrack;
	local XComGameStateHistory History;
	local GameState_RequestEvac EvacSpawnerState;
	local X2Action_PlayEffect EvacSpawnerEffectAction;
	local X2Action_PlayNarrative NarrativeAction;

	`log("DEBUG : BuildVisualizationForSpawnerCreation", , 'RequestEvac');

	History = `XCOMHISTORY;
	EvacSpawnerState = GameState_RequestEvac(History.GetGameStateForObjectID(ObjectID));

	// Temporary flare effect is the advent reinforce flare. Replace this.
	EvacSpawnerEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(BuildTrack, VisualizeGameState.GetContext(), false, BuildTrack.LastActionAdded));
	EvacSpawnerEffectAction.EffectName = "LWEvacZone.P_EvacZone_Flare";
	EvacSpawnerEffectAction.EffectLocation = EvacSpawnerState.EvacLocation;

	// Don't take control of the camera, the player knows where they put the zone.
	EvacSpawnerEffectAction.CenterCameraOnEffectDuration = 0; //ContentManager.LookAtCamDuration;
	EvacSpawnerEffectAction.bStopEffect = false;

	BuildTrack.StateObject_OldState = EvacSpawnerState;
	BuildTrack.StateObject_NewState = EvacSpawnerState;

	if (!EvacSpawnerState.SkipCreationNarrative)
	{
		NarrativeAction = X2Action_PlayNarrative(class'X2Action_PlayNarrative'.static.AddToVisualizationTree(BuildTrack, VisualizeGameState.GetContext(), false, BuildTrack.LastActionAdded));
		NarrativeAction.Moment = XComNarrativeMoment(DynamicLoadObject("X2NarrativeMoments.TACTICAL.General.SKY_Gen_EvacRequested_02", class'XComNarrativeMoment'));
		NarrativeAction.WaitForCompletion = false;
	}
}

// Countdown complete: time to spawn the evac zone.
function SpawnEvacZone()
{
	local XComGameState NewGameState;
	local X2EventManager EventManager;
	local Object ThisObj;

	EventManager = `XEVENTMGR;

	// Set up visualization of the new evac zone.
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("SpawnEvacZone");
	XComGameStateContext_ChangeContainer(NewGameState.GetContext()).BuildVisualizationFn = BuildVisualizationForEvacSpawn;

	// Place the evac zone on the map.
	class'XComGameState_EvacZone'.static.PlaceEvacZone(NewGameState, EvacLocation, eTeam_XCom);

	// Register and trigger an event to occur after we've visualized this to clean ourselves up.
	ThisObj = self;
	EventManager.RegisterForEvent(ThisObj, 'SpawnEvacZoneComplete', OnSpawnEvacZoneComplete, ELD_OnStateSubmitted,, ThisObj);
	EventManager.TriggerEvent('SpawnEvacZoneComplete', ThisObj, ThisObj, NewGameState);

	`TACTICALRULES.SubmitGameState(NewGameState);
}

// Evac zone has spawned. We can now clean ourselves up as this state object is no longer needed.
function EventListenerReturn OnSpawnEvacZoneComplete(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState NewGameState;
	local GameState_RequestEvac NewSpawnerState;

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Spawn Evac Zone Complete");
	NewSpawnerState = GameState_RequestEvac(NewGameState.CreateStateObject(class'GameState_RequestEvac', ObjectID));
	NewSpawnerState.ResetCountdown();
	NewSpawnerState.InitRemoveEvacCountdown();
	NewGameState.AddStateObject(NewSpawnerState);
	`TACTICALRULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

function BuildVisualizationForFlareDestroyed(XComGameState VisualizeState)
{
	local X2Action_PlayEffect EvacSpawnerEffectAction;
	local VisualizationActionMetadata BuildTrack;

	EvacSpawnerEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(BuildTrack, VisualizeState.GetContext(), false, BuildTrack.LastActionAdded));
	EvacSpawnerEffectAction.EffectName = "LWEvacZone.P_EvacZone_Flare";
	EvacSpawnerEffectAction.EffectLocation = EvacLocation;
	EvacSpawnerEffectAction.bStopEffect = true;
	EvacSpawnerEffectAction.bWaitForCompletion = false;
	EvacSpawnerEffectAction.bWaitForCameraCompletion = false;

	BuildTrack.StateObject_OldState = self;
	BuildTrack.StateObject_NewState = self;
}

// Visualize the evac spawn: turn off the flare we dropped as a countdown visualizer and visualize the evac zone dropping.
function BuildVisualizationForEvacSpawn(XComGameState VisualizeState)
{
	local XComGameStateHistory History;
	local XComGameState_EvacZone EvacZone;
	local VisualizationActionMetadata BuildTrack;
	local VisualizationActionMetadata EmptyTrack;
	local GameState_RequestEvac EvacSpawnerState;
	local X2Action_PlayEffect EvacSpawnerEffectAction;
	local X2Action_PlayNarrative NarrativeAction;
	local X2Action_RevealArea RevealAreaAction;

	History = `XCOMHISTORY;

	// First, get rid of our old visualization from the delayed spawn.
	EvacSpawnerState = GameState_RequestEvac(History.GetGameStateForObjectID(ObjectID));

	EvacSpawnerEffectAction = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(BuildTrack, VisualizeState.GetContext(), false, BuildTrack.LastActionAdded));
	EvacSpawnerEffectAction.EffectName = "LWEvacZone.P_EvacZone_Flare";
	EvacSpawnerEffectAction.EffectLocation = EvacSpawnerState.EvacLocation;
	EvacSpawnerEffectAction.bStopEffect = true;
	EvacSpawnerEffectAction.bWaitForCompletion = false;
	EvacSpawnerEffectAction.bWaitForCameraCompletion = false;

	BuildTrack.StateObject_OldState = EvacSpawnerState;
	BuildTrack.StateObject_NewState = EvacSpawnerState;

	// Now add the new visualization for the evac zone placement.
	BuildTrack = EmptyTrack;

	foreach VisualizeState.IterateByClassType(class'XComGameState_EvacZone', EvacZone)
	{
		break;
	}
	`assert (EvacZone != none);

	BuildTrack.StateObject_OldState = EvacZone;
	BuildTrack.StateObject_NewState = EvacZone;
	BuildTrack.VisualizeActor = EvacZone.GetVisualizer();
	class'X2Action_PlaceEvacZone'.static.AddToVisualizationTree(BuildTrack, VisualizeState.GetContext(), false, BuildTrack.LastActionAdded);
	NarrativeAction = X2Action_PlayNarrative(class'X2Action_PlayNarrative'.static.AddToVisualizationTree(BuildTrack, VisualizeState.GetContext(), false, BuildTrack.LastActionAdded));
	NarrativeAction.Moment = XComNarrativeMoment(DynamicLoadObject("LWNarrativeMoments.TACTICAL.EvacZone.Firebrand_Arrived", class'XComNarrativeMoment'));
	NarrativeAction.WaitForCompletion = false;

	RevealAreaAction = X2Action_RevealArea(class'X2Action_RevealArea'.static.AddToVisualizationTree(BuildTrack, VisualizeState.GetContext()));
	RevealAreaAction.ScanningRadius = class'XComWorldData'.const.WORLD_StepSize * 5.0f;
	RevealAreaAction.TargetLocation = EvacLocation;
	RevealAreaAction.bDestroyViewer = false;
	RevealAreaAction.AssociatedObjectID = EvacZone.ObjectID;
}

function InitEvac(int Turns, vector Loc)
{
	Countdown = Turns;
	RemoveEvacCountdown = -1;
	EvacLocation = Loc;

	`CONTENT.RequestGameArchetype("LWEvacZone.P_EvacZone_Flare");
}

// Entry point: create a delayed evac zone instance with the given countdown and position.
static function InitiateEvacZoneDeployment(int InitialCountdown, const out Vector DeploymentLocation, optional XComGameState IncomingGameState, optional bool bSkipCreationNarrative)
{
	local GameState_RequestEvac NewEvacSpawnerState;
	local XComGameState NewGameState;
	local X2EventManager EventManager;
	local Object EvacObj;

	EventManager = `XEVENTMGR;

	if (IncomingGameState == none)
	{
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Creating XCom Evac Spawner");
	}
	else
	{
		NewGameState = IncomingGameState;
	}

	NewEvacSpawnerState = GameState_RequestEvac(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'GameState_RequestEvac', true));
	if (NewEvacSpawnerState != none)
	{
		NewEvacSpawnerState = GameState_RequestEvac(NewGameState.ModifyStateObject(class'GameState_RequestEvac', NewEvacSpawnerState.ObjectID));
	}
	else
	{
		NewEvacSpawnerState = GameState_RequestEvac(NewGameState.CreateNewStateObject(class'GameState_RequestEvac'));
	}

	// Clean up any existing evac zone.
	RemoveExistingEvacZone(NewGameState);

	NewEvacSpawnerState.InitEvac(InitialCountdown, DeploymentLocation);
	NewEvacSpawnerState.SkipCreationNarrative = bSkipCreationNarrative;

	// Let others know we've requested an evac.
	EventManager.TriggerEvent('EvacRequested', NewEvacSpawnerState, NewEvacSpawnerState, NewGameState);

	// Register & immediately trigger a new event to react to the creation of this object. This should allow visualization to
	// occur in the desired order: e.g. we see the visualization of the place evac zone ability before the visualization of the state itself
	// (i.e. the flare).

	// NOTE: This event isn't intended for other parts of the code to listen to. See the 'EvacRequested' event below for that.
	EvacObj = NewEvacSpawnerState;
	EventManager.RegisterForEvent(EvacObj, 'EvacSpawnerCreated', OnEvacSpawnerCreated, ELD_OnStateSubmitted, , NewEvacSpawnerState);
	EventManager.TriggerEvent('EvacSpawnerCreated', NewEvacSpawnerState, NewEvacSpawnerState);

	if (IncomingGameState == none)
	{
		`TACTICALRULES.SubmitGameState(NewGameState);
	}
}

// Nothing to do here.
function SyncVisualizer(optional XComGameState GameState = none)
{

}

// Called when we load a saved game with an active delayed evac zone counter. Put the flare effect back up again, but don't
// focus the camera on it.
function AppendAdditionalSyncActions(out VisualizationActionMetadata ActionMetadata)
{
	local X2Action_PlayEffect PlayEffect;

	PlayEffect = X2Action_PlayEffect(class'X2Action_PlayEffect'.static.AddToVisualizationTree(ActionMetadata, GetParentGameState().GetContext(), false, ActionMetadata.LastActionAdded));

	PlayEffect.EffectName = "LWEvacZone.P_EvacZone_Flare";
	PlayEffect.EffectLocation = EvacLocation;
	PlayEffect.CenterCameraOnEffectDuration = 0;
	PlayEffect.bStopEffect = false;
}

function InitRemoveEvacCountdown()
{
	`log("DEBUG : InitRemoveEvacCountdown" @ default.TurnsBeforeEvacExpires, , 'RequestEvac');
	RemoveEvacCountdown = default.TurnsBeforeEvacExpires;
}

function int GetCountdown()
{
	return Countdown;
}

function int GetRemoveEvacCountdown()
{
	return RemoveEvacCountdown;
}

function SetCountdown(int NewCountdown)
{
	Countdown = NewCountdown;
}

function SetRemoveEvacCountdown(int NewCountdown)
{
	RemoveEvacCountdown = NewCountdown;
}

function ResetCountdown()
{
	// Clear the countdown (effectively disable the spawner)
	Countdown = -1;
}

function ResetRemoveEvacCountdown()
{
	// Clear the countdown (effectively disable the spawner)
	RemoveEvacCountdown = -1;
}

function TTile GetCenterTile()
{
	return `XWORLD.GetTileCoordinatesFromPosition(EvacLocation);
}

function static RemoveExistingEvacZone(XComGameState NewGameState)
{
	local XComGameState_EvacZone EvacZone;
	local X2Actor_EvacZone EvacZoneActor;

	EvacZone = class'XComGameState_EvacZone'.static.GetEvacZone();
	if (EvacZone == none)
		return;

	EvacZoneActor = X2Actor_EvacZone(EvacZone.GetVisualizer());
	if (EvacZoneActor == none)
		return;

	// We have an existing evac zone

	// Disable the evac ability
	class'XComGameState_BattleData'.static.SetGlobalAbilityEnabled('Evac', false, NewGameState);

	// Tell the visualizer to clean itself up.
	EvacZoneActor.Destroy();

	// Remove the evac zone state (even though we destroyed its visualizer, the state is still
	// there and will reappear if we reload the save).
	NewGameState.RemoveStateObject(EvacZone.ObjectID);

	// Stop the EvacZoneFlare environmental SFX (chopper blades/exhaust)
	//class'WorldInfo'.static.GetWorldInfo().StopAkSound('EvacZoneFlares');
}

static function GameState_RequestEvac GetPendingEvacZone()
{
	local GameState_RequestEvac EvacState;
	local XComGameStateHistory History;

	History = `XCOMHistory;
	foreach History.IterateByClassType(class'GameState_RequestEvac', EvacState)
	{
		if (EvacState.GetCountdown() > 0)
		{
			return EvacState;
		}
	}
	return none;
}

function vector GetLocation()
{
	return EvacLocation;
}

defaultproperties
{
	bTacticalTransient=true
}
