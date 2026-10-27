{*******************************************************************************
  ParticleEngine Demo Wrapper
********************************************************************************
  Threaded VCL Raylib wrapper for the Yutani.Render.Particles.GPU engine.

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

unit uParticleEngine;

interface

uses
  System.SysUtils, System.Types, System.Classes, System.Math, System.SyncObjs,
  Winapi.Windows, Winapi.MMSystem, Vcl.Controls, Raylib, rlgl, RayMath,
  Yutani.Render.Particles.GPU;

const
  SPIN_THRESHOLD_NS = 2000000;
  DEFAULT_PARTICLE_COUNT = 512000;  // 500K default - enough for all show modes including Stickman Scene

type
  THighResTimer = record
    Frequency: Int64;
    procedure Init;
    function GetTicks: Int64; inline;
    procedure HybridWaitUntil(const ATargetTicks, ASpinNanoseconds: Int64);
  end;

  TParticleEngine = class(TThread)
  private
    FParentHandle: HWND;
    FRaylibWnd: HWND;
    FTargetFPS: Integer;
    FRealFPS: Integer;
    FActive: Boolean;
    FWidth, FHeight: Integer;
    FParticles: TYutaniParticleEngine;
    FCamera: TCamera3D;
    FDesiredParticleCount: Integer;

    { Desired parameter values - stored independently of FParticles so that
      when the engine is recreated (e.g. when the user picks a new pool size),
      the current slider values can be pushed to the fresh engine. }
    FDesiredParticleScale:  Single;
    FDesiredTimeScale:      Single;
    FDesiredSigma:          Single;
    FDesiredRho:            Single;
    FDesiredBeta:           Single;
    FDesiredInstancesX1000: Single;
    FDesiredMode:           Integer;

    procedure RenderScene;
    procedure SetActive(const Value: Boolean);
    procedure PushDesiredValuesToEngine;
    procedure CheckMousePush;
  protected
    procedure Execute; override;
  public
    constructor Create(AParentHandle: HWND;
                       ANumParticles: Integer = DEFAULT_PARTICLE_COUNT);
    destructor Destroy; override;
    procedure StartEngine;
    procedure StopEngine;

    procedure Restart;
    procedure Reset;

    procedure SetParticleScale(Value: Single);
    procedure SetTimeScale(Value: Single);
    procedure SetSigma(Value: Single);
    procedure SetRho(Value: Single);
    procedure SetBeta(Value: Single);
    procedure SetInstancesX1000(Value: Single);
    procedure SetMode(Value: Integer);

    procedure SetFPS(const FPS: Integer);
    procedure SetDimensions(const W, H: Integer);
    procedure SetCamera(const Pos, Target: TVector3; Fovy: Single);

    property RealFPS: Integer read FRealFPS;
    property TargetFPS: Integer read FTargetFPS;
    property Active: Boolean read FActive write SetActive;
    property ParticleEngine: TYutaniParticleEngine read FParticles;
    property DesiredParticleCount: Integer read FDesiredParticleCount;
  end;

implementation

{ THighResTimer }

procedure THighResTimer.Init;
begin
  if not QueryPerformanceFrequency(Frequency) then
    Frequency := 0;
end;

function THighResTimer.GetTicks: Int64;
begin
  QueryPerformanceCounter(Result);
end;

procedure THighResTimer.HybridWaitUntil(const ATargetTicks, ASpinNanoseconds: Int64);
var
  SpinTicks, Remaining: Int64;
begin
  if Frequency = 0 then Exit;
  SpinTicks := (ASpinNanoseconds * Frequency) div 1000000000;
  Remaining := ATargetTicks - GetTicks;
  while Remaining > SpinTicks do
  begin
    Sleep(1);
    Remaining := ATargetTicks - GetTicks;
  end;
  while GetTicks < ATargetTicks do
    ;
end;

{ TParticleEngine }

constructor TParticleEngine.Create(AParentHandle: HWND; ANumParticles: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FParentHandle := AParentHandle;
  FTargetFPS := 60;
  FActive := False;
  FWidth := 800;
  FHeight := 800;
  FDesiredParticleCount := ANumParticles;
  FParticles := nil;

  // Camera matches main.c - particles live in (-1, 1) range so we put the
  // camera close in and let UpdateCamera(CAMERA_ORBITAL) spin it.
  FCamera.position := Vector3Create(2.0, 2.0, 2.0);
  FCamera.target := Vector3Create(0, 0, 0);
  FCamera.up := Vector3Create(0, 1, 0);
  FCamera.fovy := 35.0;
  FCamera.projection := CAMERA_PERSPECTIVE;

  // Default Lorenz parameters - same as main.c.
  FDesiredParticleScale  := 1.0;
  FDesiredTimeScale      := 0.2;
  FDesiredSigma          := 10.0;
  FDesiredRho            := 28.0;
  FDesiredBeta           := 8.0 / 3.0;
  FDesiredInstancesX1000 := 100.0;
  FDesiredMode           := 0;   { Lorenz by default }
end;

destructor TParticleEngine.Destroy;
begin
  StopEngine;
  if Assigned(FParticles) then
    FreeAndNil(FParticles);
  inherited;
end;

procedure TParticleEngine.SetDimensions(const W, H: Integer);
begin
  FWidth := W;
  FHeight := H;
  if FRaylibWnd <> 0 then
    SetWindowPos(FRaylibWnd, 0, 0, 0, FWidth, FHeight, SWP_NOZORDER or SWP_NOACTIVATE);
end;

procedure TParticleEngine.SetActive(const Value: Boolean);
begin
  if FActive <> Value then
  begin
    FActive := Value;
    if FActive and Suspended then
      Start;
  end;
end;

procedure TParticleEngine.StartEngine;
begin
  Active := True;
end;

procedure TParticleEngine.StopEngine;
begin
  Active := False;
end;

procedure TParticleEngine.SetFPS(const FPS: Integer);
begin
  if FTargetFPS <> FPS then
    FTargetFPS := FPS;
end;

procedure TParticleEngine.SetCamera(const Pos, Target: TVector3; Fovy: Single);
begin
  FCamera.position := Pos;
  FCamera.target := Target;
  FCamera.fovy := Fovy;
end;

{ ============================================================================
  Push desired parameter values to the freshly-created engine.
  Called from Execute after FParticles.Initialise succeeds.
  ============================================================================ }

procedure TParticleEngine.PushDesiredValuesToEngine;
begin
  if not Assigned(FParticles) then Exit;
  FParticles.ParticleScale  := FDesiredParticleScale;
  FParticles.TimeScale      := FDesiredTimeScale;
  FParticles.Sigma          := FDesiredSigma;
  FParticles.Rho            := FDesiredRho;
  FParticles.Beta           := FDesiredBeta;
  FParticles.InstancesX1000 := FDesiredInstancesX1000;
  FParticles.Mode           := FDesiredMode;
end;

{ ============================================================================
  Mouse push - reads the Raylib mouse state and converts screen-space mouse
  position to a world-space push point via manual camera-vector math (no
  GetMouseRay dependency - that function isn't exported by all raylib DLL
  builds). When the left mouse button is held in the Raylib window, particles
  near the push point get a velocity impulse away from it.
  ============================================================================ }

procedure TParticleEngine.CheckMousePush;
var
  MX, MY, SW, SH: Integer;
  Eye, Target, Up, Fwd, Right, RealUp: TVector3;
  NdcX, NdcY, Dist, TanFovy, Aspect: Single;
  PushPos: TVector3;
begin
  if not Assigned(FParticles) then Exit;

  if IsMouseButtonDown(MOUSE_LEFT_BUTTON) then
  begin
    MX := GetMouseX;
    MY := GetMouseY;
    SW := FWidth;
    SH := FHeight;
    if SW <= 0 then SW := 1;
    if SH <= 0 then SH := 1;

    Eye := FCamera.position;
    Target := FCamera.target;
    Up := FCamera.up;

    // Forward = normalize(Target - Eye)
    Fwd.x := Target.x - Eye.x;
    Fwd.y := Target.y - Eye.y;
    Fwd.z := Target.z - Eye.z;
    Dist := Sqrt(Fwd.x*Fwd.x + Fwd.y*Fwd.y + Fwd.z*Fwd.z);
    if Dist > 0.001 then
    begin
      Fwd.x := Fwd.x / Dist; Fwd.y := Fwd.y / Dist; Fwd.z := Fwd.z / Dist;
    end;

    // Right = normalize(cross(Fwd, Up))
    Right.x := Fwd.y * Up.z - Fwd.z * Up.y;
    Right.y := Fwd.z * Up.x - Fwd.x * Up.z;
    Right.z := Fwd.x * Up.y - Fwd.y * Up.x;
    Dist := Sqrt(Right.x*Right.x + Right.y*Right.y + Right.z*Right.z);
    if Dist > 0.001 then
    begin
      Right.x := Right.x / Dist; Right.y := Right.y / Dist; Right.z := Right.z / Dist;
    end;

    // RealUp = cross(Right, Fwd)
    RealUp.x := Right.y * Fwd.z - Right.z * Fwd.y;
    RealUp.y := Right.z * Fwd.x - Right.x * Fwd.z;
    RealUp.z := Right.x * Fwd.y - Right.y * Fwd.x;

    // Distance from camera to target (origin)
    Dist := Sqrt(Sqr(Eye.x - Target.x) + Sqr(Eye.y - Target.y) + Sqr(Eye.z - Target.z));

    // Normalized Device Coordinates from mouse position
    NdcX := (2.0 * MX / SW) - 1.0;
    NdcY := 1.0 - (2.0 * MY / SH);

    // FOV-based projection at camera-target distance
    TanFovy := System.Math.Tan(FCamera.fovy * 0.5 * Pi / 180.0);
    Aspect := SW / SH;

    // World-space point where the mouse is pointing at camera-target depth
    PushPos.x := Eye.x + Fwd.x * Dist + Right.x * NdcX * TanFovy * Aspect * Dist
                 + RealUp.x * NdcY * TanFovy * Dist;
    PushPos.y := Eye.y + Fwd.y * Dist + Right.y * NdcX * TanFovy * Aspect * Dist
                 + RealUp.y * NdcY * TanFovy * Dist;
    PushPos.z := Eye.z + Fwd.z * Dist + Right.z * NdcX * TanFovy * Aspect * Dist
                 + RealUp.z * NdcY * TanFovy * Dist;

    FParticles.SetPush(PushPos, 0.3, 8.0);
  end
  else
    FParticles.ClearPush;
end;

{ ============================================================================
  Simulation control - mirror of main.c's Restart/Reset buttons.
  ============================================================================ }

procedure TParticleEngine.Restart;
begin
  if Assigned(FParticles) then
    FParticles.Restart;
end;

procedure TParticleEngine.Reset;
begin
  // Reset the in-engine params AND the FDesired* fields (so a future
  // engine recreation uses the defaults too).
  FDesiredParticleScale  := 1.0;
  FDesiredTimeScale      := 0.2;
  FDesiredSigma          := 10.0;
  FDesiredRho            := 28.0;
  FDesiredBeta           := 8.0 / 3.0;
  FDesiredInstancesX1000 := 100.0;
  FDesiredMode           := 0;   { Lorenz }
  if Assigned(FParticles) then
    FParticles.Reset;
end;

{ ============================================================================
  Parameter setters - store desired value AND push to live engine if ready.
  ============================================================================ }

procedure TParticleEngine.SetParticleScale(Value: Single);
begin
  FDesiredParticleScale := Value;
  if Assigned(FParticles) then
    FParticles.ParticleScale := Value;
end;

procedure TParticleEngine.SetTimeScale(Value: Single);
begin
  FDesiredTimeScale := Value;
  if Assigned(FParticles) then
    FParticles.TimeScale := Value;
end;

procedure TParticleEngine.SetSigma(Value: Single);
begin
  FDesiredSigma := Value;
  if Assigned(FParticles) then
    FParticles.Sigma := Value;
end;

procedure TParticleEngine.SetRho(Value: Single);
begin
  FDesiredRho := Value;
  if Assigned(FParticles) then
    FParticles.Rho := Value;
end;

procedure TParticleEngine.SetBeta(Value: Single);
begin
  FDesiredBeta := Value;
  if Assigned(FParticles) then
    FParticles.Beta := Value;
end;

procedure TParticleEngine.SetInstancesX1000(Value: Single);
begin
  FDesiredInstancesX1000 := Value;
  if Assigned(FParticles) then
    FParticles.InstancesX1000 := Value;
end;

procedure TParticleEngine.SetMode(Value: Integer);
begin
  FDesiredMode := Value;
  if Assigned(FParticles) then
    FParticles.SetMode(Value);
end;

procedure TParticleEngine.RenderScene;
begin
  BeginDrawing();
  ClearBackground(BLACK);

  // Orbit the camera around the origin - matches main.c's
  // UpdateCamera(&camera, CAMERA_ORBITAL).
  UpdateCamera(@FCamera, CAMERA_ORBITAL);

  rlEnableDepthTest();
  rlDisableBackfaceCulling();
  BeginMode3D(FCamera);
  try
    DrawCubeWires(Vector3Create(0, 0, 0), 1.0, 1.0, 1.0, DARKGRAY);
    if Assigned(FParticles) then
      FParticles.Render(FCamera);
  finally
    EndMode3D();
  end;

  rlEnableBackfaceCulling();
  rlDisableDepthTest();

  // ========================================================================
  // NOTE: We deliberately do NOT call DrawText() here to render FPS / N
  // labels inside the Raylib window. The GPU particle engine leaves OpenGL
  // state in a custom configuration (raw GL shaders bound, SSBOs on slots
  // 0..2, custom blend mode). Even with the cache-busting logic in
  // TYutaniParticleEngine.DrawInstances (rlSetShader default, glActiveTexture,
  // glBindTexture reset), Raylib's DrawText still occasionally renders as
  // solid colored blocks instead of glyphs - the font atlas binding gets
  // out of sync between our raw-GL pass and Raylib's text batching.
  //
  // Instead, FPS + active particle count are shown as VCL labels in
  // Unit1.pas, completely independent of the Raylib render window.
  // ========================================================================

  EndDrawing();

  if FRaylibWnd <> 0 then
    RedrawWindow(FRaylibWnd, nil, 0, RDW_INVALIDATE or RDW_UPDATENOW);
end;

procedure TParticleEngine.Execute;
var
  Timer: THighResTimer;
  Freq, FrameTicks: Int64;
  NextFrame, NowTicks, LastFrameTicks: Int64;
  DeltaSec: Double;
  FrameCount: Integer;
  LastFpsTime: Int64;
  WindowName: AnsiString;
begin
  {$IFDEF MSWINDOWS}
  timeBeginPeriod(1);
  {$ENDIF}
  try
    SetConfigFlags(FLAG_MSAA_4X_HINT);
    WindowName := AnsiString('ParticleEngine_' + IntToStr(IntPtr(Self)));
    InitWindow(FWidth, FHeight, PAnsiChar(WindowName));

    FRaylibWnd := FindWindowA(nil, PAnsiChar(WindowName));
    if (FRaylibWnd <> 0) and (FParentHandle <> 0) then
    begin
      Winapi.Windows.SetParent(FRaylibWnd, FParentHandle);
      SetWindowLong(FRaylibWnd, GWL_STYLE, WS_CHILD or WS_VISIBLE);
      SetWindowPos(FRaylibWnd, 0, 0, 0, FWidth, FHeight, SWP_NOZORDER or SWP_NOACTIVATE);
    end;

    // Create + initialise the compute-shader particle engine HERE.
    FParticles := TYutaniParticleEngine.Create(FDesiredParticleCount);
    FParticles.Initialise;

    // Push the currently-desired parameter values to the fresh engine.
    // This matters when the engine was recreated (e.g. after the user
    // picked a new pool size in the VCL form) - the slider values that
    // were set before recreation now need to land on the new FParticles.
    PushDesiredValuesToEngine;

    // Initialize frame pacing timers
    Timer.Init;
    Freq := Timer.Frequency;
    if Freq <= 0 then Freq := 10000000;
    NowTicks := Timer.GetTicks;
    LastFrameTicks := NowTicks;
    NextFrame := NowTicks;
    LastFpsTime := NowTicks;
    FrameCount := 0;

    while not Terminated do
    begin
      if WindowShouldClose() then Break;

      NowTicks := Timer.GetTicks;
      DeltaSec := (NowTicks - LastFrameTicks) / Freq;
      LastFrameTicks := NowTicks;

      if (DeltaSec <= 0) or (DeltaSec > 0.25) then
        DeltaSec := 1 / 60;

      if FActive then
      begin
        // Check mouse interaction before Update - if the user is holding
        // left mouse button in the Raylib window, push particles away.
        CheckMousePush;
        if Assigned(FParticles) then
          FParticles.Update(DeltaSec);
      end;
      RenderScene;

      Inc(FrameCount);
      if (NowTicks - LastFpsTime) >= Freq then
      begin
        FRealFPS := Round(FrameCount * Freq / (NowTicks - LastFpsTime));
        FrameCount := 0;
        LastFpsTime := NowTicks;
      end;

      if FTargetFPS > 0 then
        FrameTicks := Round(Freq / FTargetFPS)
      else
        FrameTicks := Freq div 60;
      NextFrame := NextFrame + FrameTicks;

      NowTicks := Timer.GetTicks;
      if (NowTicks - NextFrame) > Freq then
        NextFrame := NowTicks;

      Timer.HybridWaitUntil(NextFrame, SPIN_THRESHOLD_NS);
    end;
  finally
    FreeAndNil(FParticles);
    if FRaylibWnd <> 0 then
      CloseWindow();
    {$IFDEF MSWINDOWS}
    timeEndPeriod(1);
    {$ENDIF}
  end;
end;

end.
