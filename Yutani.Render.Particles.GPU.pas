{*******************************************************************************
  Yutani.Render.Particles.GPU v0.2
********************************************************************************
  GPU compute-shader particle engine with 60 modes + global forces + HDR.

  Show modes (0-11): Lorenz, Cube, Sphere, Wave, Galaxy, Fountain, Vortex,
    DNA Helix, Black Hole, Explode, Flow Field, Stickman Scene

  Emitter modes (12-59): Fog, Fire, Rain, Snow, Smoke, Explosion, Sparks,
    Fountain2, Storm, Dust, Ants, BlackGoo, Bubbles, Fireflies, Leaves,
    Energy, Plasma, Lightning, Ash, Debris, Steam, SnowDrift, Insects,
    Swarm, Beam, Portal, Crystal, PixieDust, GhostMist, Comet, Shockwave,
    RainSplash, LavaBubble, StarField, Nebula, Tornado, Glow, VolLight,
    Sandstorm, Hailstorm, Whirlpool, Mushroom, SmokeColumn, BlackSmoke,
    EngineExhaust, SparkTrail, MagicMissile, Clouds (FBM noise)

  Features:
    - Custom color/alpha/size per emitter mode (emColorR/G/B/A, emSize uniforms)
    - Global forces (globalWind, globalGravity vec3 uniforms)
    - HDR multiplier for bloom post-processing
    - Manual camera (arrow keys + middle-mouse drag + wheel zoom)
    - Auto-rotate toggle
    - FBM noise functions for organic cloud formations

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

unit Yutani.Render.Particles.GPU;

{$POINTERMATH ON}

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  Winapi.Windows,
  Raylib, RayMath, rlgl;

type
  TYutaniParticleEngine = class
  private
    FLock: TCriticalSection;
    FComputeProgram:      Cardinal;
    FRenderProgram:      Cardinal;
    FSSBO_Positions:      Cardinal;
    FSSBO_Velocities:     Cardinal;
    FSSBO_StartPositions: Cardinal;
    FBillboardVAO:        Cardinal;
    FBillboardVBO:        Cardinal;
    FNumParticles:   Integer;
    FParticleScale:  Single;
    FTimeScale:      Single;
    FSigma:          Single;
    FRho:            Single;
    FBeta:           Single;
    FTime:           Single;
    FInstancesX1000: Single;
    FMode:           Integer;
    FNeedsReset:     Boolean;
    FPushPos:        TVector3;
    FPushRadius:     Single;
    FPushStrength:   Single;
    FPushActive:     Boolean;
    FGPUInitialized: Boolean;
    FEmColorR:       Single;
    FEmColorG:       Single;
    FEmColorB:       Single;
    FEmColorA:       Single;
    FEmSize:         Single;
    FGlobalWind:     TVector3;
    FGlobalGravity:  TVector3;
    FHDRMultiplier:  Single;
    FCompLoc_Time:           Integer;
    FCompLoc_TimeScale:      Integer;
    FCompLoc_DeltaTime:      Integer;
    FCompLoc_Sigma:          Integer;
    FCompLoc_Rho:            Integer;
    FCompLoc_Beta:           Integer;
    FCompLoc_Mode:           Integer;
    FCompLoc_ParticleCount:  Integer;
    FCompLoc_PushPos:        Integer;
    FCompLoc_PushRadius:     Integer;
    FCompLoc_PushStrength:   Integer;
    FCompLoc_PushActive:     Integer;
    FCompLoc_EmColorR:      Integer;
    FCompLoc_EmColorG:      Integer;
    FCompLoc_EmColorB:      Integer;
    FCompLoc_EmColorA:      Integer;
    FCompLoc_GlobalWind:    Integer;
    FCompLoc_GlobalGravity: Integer;
    FRendLoc_ProjMatrix:    Integer;
    FRendLoc_ViewMatrix:    Integer;
    FRendLoc_ParticleScale: Integer;
    FRendLoc_EmColorR:     Integer;
    FRendLoc_EmColorG:     Integer;
    FRendLoc_EmColorB:     Integer;
    FRendLoc_EmColorA:     Integer;
    FRendLoc_EmSize:        Integer;
    FRendLoc_HDRMultiplier:  Integer;
    procedure InitGPUResources;
    procedure FreeGPUResources;
    procedure BuildBillboardVAO;
    procedure DispatchCompute(const dt: Single);
    procedure DrawInstances(const NumInstances: Integer; const ACamera: TCamera3D);
    function  GetActiveInstanceCount: Integer;
  public
    constructor Create(ANumParticles: Integer = 102400);
    destructor  Destroy; override;
    procedure Initialise;
    procedure Update(const ADeltaTime: Single);
    procedure Render(const ACamera: TCamera3D);
    procedure Restart;
    procedure Reset;
    procedure SetMode(AMode: Integer);
    procedure SetPush(const APos: TVector3; ARadius, AStrength: Single);
    procedure ClearPush;
    procedure SetEmColor(R, G, B, A: Single);
    procedure SetEmSize(S: Single);
    procedure SetGlobalWind(X, Y, Z: Single);
    procedure SetGlobalGravity(X, Y, Z: Single);
    procedure SetHDRMultiplier(M: Single);
    property NumParticles:        Integer read FNumParticles;
    property ParticleScale:       Single  read FParticleScale  write FParticleScale;
    property TimeScale:           Single  read FTimeScale      write FTimeScale;
    property Sigma:               Single  read FSigma          write FSigma;
    property Rho:                 Single  read FRho            write FRho;
    property Beta:               Single  read FBeta            write FBeta;
    property Time:                Single  read FTime           write FTime;
    property InstancesX1000:      Single  read FInstancesX1000 write FInstancesX1000;
    property Mode:                Integer read FMode            write FMode;
    property PushActive:          Boolean read FPushActive;
    property ActiveInstanceCount: Integer read GetActiveInstanceCount;
    property ParticleCount:       Integer read GetActiveInstanceCount;
  end;

implementation

{ ========================================================================== }
{ OpenGL 4.3+ dynamic function loading                                       }
{ ========================================================================== }

const
  GL_COMPUTE_SHADER              = $91B9;
  GL_VERTEX_SHADER               = $8B31;
  GL_FRAGMENT_SHADER             = $8B30;
  GL_COMPILE_STATUS              = $8B81;
  GL_LINK_STATUS                 = $8B82;
  GL_INFO_LOG_LENGTH             = $8B84;
  GL_SHADER_STORAGE_BARRIER_BIT  = $2000;
  GL_FALSE                       = 0;
  GL_TRUE                        = 1;
  GL_CULL_FACE                   = $0B44;
  GL_DEPTH_TEST                  = $0B71;
  GL_BLEND                       = $0BE2;
  GL_SRC_ALPHA                   = $0302;
  GL_ONE_MINUS_SRC_ALPHA         = $0303;
  GL_ARRAY_BUFFER                = $8892;
  GL_ELEMENT_ARRAY_BUFFER        = $8893;
  GL_SHADER_STORAGE_BUFFER       = $90D2;
  GL_STATIC_DRAW                 = $88E4;
  GL_DYNAMIC_COPY                = $88EA;
  GL_DYNAMIC_DRAW                = $88E8;
  GL_TRIANGLES                   = $0004;
  GL_NO_ERROR                    = 0;
  GL_FLOAT                       = $1406;
  GL_TEXTURE0                    = $84C0;
  GL_TEXTURE_2D                  = $0DE1;

type
  PFNGLCREATESHADERPROC        = function(shaderType: Cardinal): Cardinal; stdcall;
  PFNGLSHADERSOURCEPROC        = procedure(shader: Cardinal; count: Integer; str: PPAnsiChar; len: PInteger); stdcall;
  PFNGLCOMPILESHADERPROC       = procedure(shader: Cardinal); stdcall;
  PFNGLDELETESHADERPROC        = procedure(shader: Cardinal); stdcall;
  PFNGLGETSHADERIVPROC         = procedure(shader: Cardinal; pname: Cardinal; params: PInteger); stdcall;
  PFNGLGETSHADERINFOLOGPROC    = procedure(shader: Cardinal; bufSize: Integer; length: PInteger; infoLog: PAnsiChar); stdcall;
  PFNGLCREATEPROGRAMPROC       = function: Cardinal; stdcall;
  PFNGLATTACHSHADERPROC        = procedure(programObj: Cardinal; shader: Cardinal); stdcall;
  PFNGLLINKPROGRAMPROC        = procedure(programObj: Cardinal); stdcall;
  PFNGLDELETEPROGRAMPROC      = procedure(programObj: Cardinal); stdcall;
  PFNGLGETPROGRAMIVPROC        = procedure(programObj: Cardinal; pname: Cardinal; params: PInteger); stdcall;
  PFNGLGETPROGRAMINFOLOGPROC  = procedure(programObj: Cardinal; bufSize: Integer; length: PInteger; infoLog: PAnsiChar); stdcall;
  PFNGLUSEPROGRAMPROC         = procedure(programObj: Cardinal); stdcall;
  PFNGLGETUNIFORMLOCATIONPROC = function(programObj: Cardinal; name: PAnsiChar): Integer; stdcall;
  PFNGLUNIFORM1FPROC           = procedure(location: Integer; v: Single); stdcall;
  PFNGLUNIFORM1IPROC           = procedure(location: Integer; v: Integer); stdcall;
  PFNGLUNIFORM1UIPROC          = procedure(location: Integer; v: Cardinal); stdcall;
  PFNGLUNIFORM3FPROC           = procedure(location: Integer; x: Single; y: Single; z: Single); stdcall;
  PFNGLUNIFORMMATRIX4FVPROC    = procedure(location: Integer; count: Integer; transpose: Byte; value: PSingle); stdcall;
  PFNGLDISPATCHCOMPUTEPROC    = procedure(num_groups_x, num_groups_y, num_groups_z: Cardinal); stdcall;
  PFNGLMEMORYBARRIERPROC      = procedure(barriers: Cardinal); stdcall;
  PFNGLGENVERTEXARRAYSPROC    = procedure(n: Integer; arrays: PCardinal); stdcall;
  PFNGLBINDVERTEXARRAYPROC    = procedure(array_: Cardinal); stdcall;
  PFNGLDELETEVERTEXARRAYSPROC = procedure(n: Integer; arrays: PCardinal); stdcall;
  PFNGLGENBUFFERSPROC         = procedure(n: Integer; buffers: PCardinal); stdcall;
  PFNGLDELETEBUFFERSPROC      = procedure(n: Integer; buffers: PCardinal); stdcall;
  PFNGLBINDBUFFERPROC         = procedure(target: Cardinal; buffer: Cardinal); stdcall;
  PFNGLBUFFERDATAPROC         = procedure(target: Cardinal; size: NativeInt; data: Pointer; usage: Cardinal); stdcall;
  PFNGLBUFFERSUBDATAPROC      = procedure(target: Cardinal; offset: NativeInt; size: NativeInt; data: Pointer); stdcall;
  PFNGLGETBUFFERSUBDATAPROC   = procedure(target: Cardinal; offset: NativeInt; size: NativeInt; data: Pointer); stdcall;
  PFNGLBINDBUFFERBASEPROC     = procedure(target: Cardinal; index: Cardinal; buffer: Cardinal); stdcall;
  PFNGLVERTEXATTRIBPOINTERPROC = procedure(index: Cardinal; size: Integer; type_: Cardinal; normalized: Byte; stride: Integer; pointer: Pointer); stdcall;
  PFNGLENABLEVERTEXATTRIBARRAYPROC = procedure(index: Cardinal); stdcall;
  PFNGLDRAWARRAYSINSTANCEDPROC = procedure(mode: Cardinal; first: Integer; count: Integer; instancecount: Integer); stdcall;
  PFNGLGETERRORPROC           = function: Cardinal; stdcall;
  PFNGLACTIVETEXTUREPROC       = procedure(texture: Cardinal); stdcall;

function wglGetProcAddress(name: PAnsiChar): Pointer; stdcall; external 'opengl32.dll';
procedure OutputDebugStringA(lpOutputString: PAnsiChar); stdcall; external 'kernel32.dll';
function rlGetShaderIdDefault: Cardinal; cdecl; external {$IFNDEF RAY_STATIC}cDllName{$ENDIF} name 'rlGetShaderIdDefault';
function rlGetShaderLocsDefault: PInteger; cdecl; external {$IFNDEF RAY_STATIC}cDllName{$ENDIF} name 'rlGetShaderLocsDefault';
procedure glDisable(cap: Cardinal); stdcall; external 'opengl32.dll';
procedure glEnable(cap: Cardinal); stdcall; external 'opengl32.dll';
procedure glDepthMask(flag: Byte); stdcall; external 'opengl32.dll';
procedure glBlendFunc(sfactor, dfactor: Cardinal); stdcall; external 'opengl32.dll';
procedure glBindTexture(target: Cardinal; texture: Cardinal); stdcall; external 'opengl32.dll';

var
  glGenVertexArrays: PFNGLGENVERTEXARRAYSPROC;
  glBindVertexArray: PFNGLBINDVERTEXARRAYPROC;
  glDeleteVertexArrays: PFNGLDELETEVERTEXARRAYSPROC;
  glGenBuffers: PFNGLGENBUFFERSPROC;
  glDeleteBuffers: PFNGLDELETEBUFFERSPROC;
  glBindBuffer: PFNGLBINDBUFFERPROC;
  glBufferData: PFNGLBUFFERDATAPROC;
  glBufferSubData: PFNGLBUFFERSUBDATAPROC;
  glGetBufferSubData: PFNGLGETBUFFERSUBDATAPROC;
  glBindBufferBase: PFNGLBINDBUFFERBASEPROC;
  glVertexAttribPointer: PFNGLVERTEXATTRIBPOINTERPROC;
  glEnableVertexAttribArray: PFNGLENABLEVERTEXATTRIBARRAYPROC;
  glDrawArraysInstanced: PFNGLDRAWARRAYSINSTANCEDPROC;
  glGetError: PFNGLGETERRORPROC;
  glActiveTexture: PFNGLACTIVETEXTUREPROC;
  glCreateShader: PFNGLCREATESHADERPROC;
  glShaderSource: PFNGLSHADERSOURCEPROC;
  glCompileShader: PFNGLCOMPILESHADERPROC;
  glDeleteShader: PFNGLDELETESHADERPROC;
  glGetShaderiv: PFNGLGETSHADERIVPROC;
  glGetShaderInfoLog: PFNGLGETSHADERINFOLOGPROC;
  glCreateProgram: PFNGLCREATEPROGRAMPROC;
  glAttachShader: PFNGLATTACHSHADERPROC;
  glLinkProgram: PFNGLLINKPROGRAMPROC;
  glDeleteProgram: PFNGLDELETEPROGRAMPROC;
  glGetProgramiv: PFNGLGETPROGRAMIVPROC;
  glGetProgramInfoLog: PFNGLGETPROGRAMINFOLOGPROC;
  glUseProgram: PFNGLUSEPROGRAMPROC;
  glGetUniformLocation: PFNGLGETUNIFORMLOCATIONPROC;
  glUniform1f: PFNGLUNIFORM1FPROC;
  glUniform1i: PFNGLUNIFORM1IPROC;
  glUniform1ui: PFNGLUNIFORM1UIPROC;
  glUniform3f: PFNGLUNIFORM3FPROC;
  glUniformMatrix4fv: PFNGLUNIFORMMATRIX4FVPROC;
  glDispatchCompute: PFNGLDISPATCHCOMPUTEPROC;
  glMemoryBarrier: PFNGLMEMORYBARRIERPROC;
  GLReady: Boolean = False;

function LoadOpenGL43: Boolean;
  function GetProc(const name: AnsiString): Pointer;
  begin
    Result := wglGetProcAddress(PAnsiChar(name));
    if Result = nil then
      Result := GetProcAddress(GetModuleHandle('opengl32.dll'), PAnsiChar(name));
  end;
begin
  if GLReady then Exit(True);
  glCreateShader := GetProc('glCreateShader');
  glShaderSource := GetProc('glShaderSource');
  glCompileShader := GetProc('glCompileShader');
  glDeleteShader := GetProc('glDeleteShader');
  glGetShaderiv := GetProc('glGetShaderiv');
  glGetShaderInfoLog := GetProc('glGetShaderInfoLog');
  glCreateProgram := GetProc('glCreateProgram');
  glAttachShader := GetProc('glAttachShader');
  glLinkProgram := GetProc('glLinkProgram');
  glDeleteProgram := GetProc('glDeleteProgram');
  glGetProgramiv := GetProc('glGetProgramiv');
  glGetProgramInfoLog := GetProc('glGetProgramInfoLog');
  glUseProgram := GetProc('glUseProgram');
  glGetUniformLocation := GetProc('glGetUniformLocation');
  glUniform1f := GetProc('glUniform1f');
  glUniform1i := GetProc('glUniform1i');
  glUniform1ui := GetProc('glUniform1ui');
  glUniform3f := GetProc('glUniform3f');
  glUniformMatrix4fv := GetProc('glUniformMatrix4fv');
  glDispatchCompute := GetProc('glDispatchCompute');
  glMemoryBarrier := GetProc('glMemoryBarrier');
  glGenVertexArrays := GetProc('glGenVertexArrays');
  glBindVertexArray := GetProc('glBindVertexArray');
  glDeleteVertexArrays := GetProc('glDeleteVertexArrays');
  glGenBuffers := GetProc('glGenBuffers');
  glDeleteBuffers := GetProc('glDeleteBuffers');
  glBindBuffer := GetProc('glBindBuffer');
  glBufferData := GetProc('glBufferData');
  glBufferSubData := GetProc('glBufferSubData');
  glGetBufferSubData := GetProc('glGetBufferSubData');
  glBindBufferBase := GetProc('glBindBufferBase');
  glVertexAttribPointer := GetProc('glVertexAttribPointer');
  glEnableVertexAttribArray := GetProc('glEnableVertexAttribArray');
  glDrawArraysInstanced := GetProc('glDrawArraysInstanced');
  glGetError := GetProc('glGetError');
  glActiveTexture := GetProc('glActiveTexture');
  GLReady := Assigned(glCreateShader) and Assigned(glShaderSource) and
    Assigned(glCompileShader) and Assigned(glDeleteShader) and
    Assigned(glGetShaderiv) and Assigned(glGetShaderInfoLog) and
    Assigned(glCreateProgram) and Assigned(glAttachShader) and
    Assigned(glLinkProgram) and Assigned(glDeleteProgram) and
    Assigned(glGetProgramiv) and Assigned(glGetProgramInfoLog) and
    Assigned(glUseProgram) and Assigned(glGetUniformLocation) and
    Assigned(glUniform1f) and Assigned(glUniform1i) and
    Assigned(glUniform1ui) and Assigned(glUniform3f) and
    Assigned(glUniformMatrix4fv) and Assigned(glDispatchCompute) and
    Assigned(glMemoryBarrier) and Assigned(glGenVertexArrays) and
    Assigned(glBindVertexArray) and Assigned(glDeleteVertexArrays) and
    Assigned(glGenBuffers) and Assigned(glDeleteBuffers) and
    Assigned(glBindBuffer) and Assigned(glBufferData) and
    Assigned(glBufferSubData) and Assigned(glGetBufferSubData) and
    Assigned(glBindBufferBase) and Assigned(glVertexAttribPointer) and
    Assigned(glEnableVertexAttribArray) and Assigned(glDrawArraysInstanced) and
    Assigned(glGetError) and Assigned(glActiveTexture);
  Result := GLReady;
end;

function CompileShaderRaw(const src: AnsiString; shaderType: Cardinal): Cardinal;
var srcPtr: PAnsiChar; srcLen: Integer; success: Integer;
    infoLog: array[0..4095] of AnsiChar; typeName: string;
begin
  Result := 0;
  case shaderType of
    GL_COMPUTE_SHADER: typeName := 'COMPUTE';
    GL_VERTEX_SHADER: typeName := 'VERTEX';
    GL_FRAGMENT_SHADER: typeName := 'FRAGMENT';
    else typeName := 'UNKNOWN';
  end;
  Result := glCreateShader(shaderType);
  if Result = 0 then raise Exception.CreateFmt('glCreateShader(%s) returned 0', [typeName]);
  srcPtr := PAnsiChar(src); srcLen := Length(src);
  glShaderSource(Result, 1, @srcPtr, @srcLen);
  glCompileShader(Result);
  glGetShaderiv(Result, GL_COMPILE_STATUS, @success);
  if success = GL_FALSE then begin
    FillChar(infoLog, SizeOf(infoLog), 0);
    glGetShaderInfoLog(Result, SizeOf(infoLog), nil, infoLog);
    glDeleteShader(Result); Result := 0;
    raise Exception.CreateFmt('Yutani.Render.Particles.GPU: %s shader compile FAILED:'#10#10'%s', [typeName, string(infoLog)]);
  end;
end;

function LinkProgramRaw(const shaderIds: array of Cardinal): Cardinal;
var i: Integer; success: Integer; infoLog: array[0..4095] of AnsiChar;
begin
  Result := glCreateProgram();
  if Result = 0 then raise Exception.Create('glCreateProgram() returned 0');
  for i := Low(shaderIds) to High(shaderIds) do glAttachShader(Result, shaderIds[i]);
  glLinkProgram(Result);
  glGetProgramiv(Result, GL_LINK_STATUS, @success);
  if success = GL_FALSE then begin
    FillChar(infoLog, SizeOf(infoLog), 0);
    glGetProgramInfoLog(Result, SizeOf(infoLog), nil, infoLog);
    glDeleteProgram(Result); Result := 0;
    raise Exception.CreateFmt('Yutani.Render.Particles.GPU: shader program link FAILED:'#10#10'%s', [string(infoLog)]);
  end;
  for i := Low(shaderIds) to High(shaderIds) do glDeleteShader(shaderIds[i]);
end;

{ ========================================================================== }
{ Embedded shader sources                                                   }
{ ========================================================================== }

const
  COMPUTE_SHADER_SRC: AnsiString =
    '#version 430'#10 +
    'layout(local_size_x = 1024) in;'#10 +
    'layout(std430, binding=0) buffer ssbo0 { vec4 positions[]; };'#10 +
    'layout(std430, binding=1) buffer ssbo1 { vec4 velocities[]; };'#10 +
    'layout(std430, binding=2) buffer ssbo2 { vec4 startPositions[]; };'#10 +
    'layout(location=0) uniform float time;'#10 +
    'layout(location=1) uniform float timeScale;'#10 +
    'layout(location=2) uniform float deltaTime;'#10 +
    'layout(location=3) uniform float sigma;'#10 +
    'layout(location=4) uniform float rho;'#10 +
    'layout(location=5) uniform float beta;'#10 +
    'layout(location=6) uniform int mode;'#10 +
    'layout(location=7) uniform int particleCount;'#10 +
    'layout(location=8) uniform vec3 pushPos;'#10 +
    'layout(location=9) uniform float pushRadius;'#10 +
    'layout(location=10) uniform float pushStrength;'#10 +
    'layout(location=11) uniform int pushActive;'#10 +
    'layout(location=12) uniform float emColorR;'#10 +
    'layout(location=13) uniform float emColorG;'#10 +
    'layout(location=14) uniform float emColorB;'#10 +
    'layout(location=15) uniform float emColorA;'#10 +
    'layout(location=16) uniform vec3 globalWind;'#10 +
    'layout(location=17) uniform vec3 globalGravity;'#10 +
    'const float PI = 3.14159;'#10 +
    'float rand(float n) { return fract(sin(n*12.9898)*43758.5453); }'#10 +
    'void main() {'#10 +
    '    uint index = gl_GlobalInvocationID.x;'#10 +
    '    if (index >= uint(particleCount)) return;'#10 +
    '    vec3 pos = positions[index].xyz;'#10 +
    '    vec3 vel = velocities[index].xyz;'#10 +
    '    float colorIdx = 0.0; // 0=velocity-rainbow, >0=fixed color per element'#10 +
    '    if (time == 0.0) { pos = startPositions[index].xyz; vel = vec3(0.0); }'#10 +
    '    if (mode == 0) {'#10 +
    '        vec3 lp = 30.0*pos + vec3(0.0,0.0,30.0);'#10 +
    '        vel.x = sigma*(lp.y-lp.x); vel.y = lp.x*(rho-lp.z)-lp.y; vel.z = lp.x*lp.y-beta*lp.z;'#10 +
    '        lp += vel*deltaTime*timeScale; pos = (lp-vec3(0.0,0.0,30.0))/30.0;'#10 +
    '    } else if (mode == 1) {'#10 +
    '        int f = int(mod(float(index),6.0));'#10 +
    '        float u = (rand(float(index)*1.7)-0.5)*1.4; float v = (rand(float(index)*2.3)-0.5)*1.4; float s = 0.7;'#10 +
    '        vec3 t;'#10 +
    '        if (f==0) t=vec3(s,u,v); else if (f==1) t=vec3(-s,u,v); else if (f==2) t=vec3(u,s,v);'#10 +
    '        else if (f==3) t=vec3(u,-s,v); else if (f==4) t=vec3(u,v,s); else t=vec3(u,v,-s);'#10 +
    '        pos = mix(pos,t,0.03); vel = (t-pos)*5.0;'#10 +
    '    } else if (mode == 2) {'#10 +
    '        float i = float(index)+0.5; float phi = acos(1.0-2.0*i/float(particleCount));'#10 +
    '        float th = PI*(1.0+sqrt(5.0))*i; float r = 0.7;'#10 +
    '        vec3 t = vec3(r*sin(phi)*cos(th), r*sin(phi)*sin(th), r*cos(phi));'#10 +
    '        float a = time*0.3; float c = cos(a); float s = sin(a);'#10 +
    '        t = vec3(c*t.x-s*t.z, t.y, s*t.x+c*t.z);'#10 +
    '        pos = mix(pos,t,0.03); vel = (t-pos)*5.0;'#10 +
    '    } else if (mode == 3) {'#10 +
    '        vec3 p = pos*4.0 + vec3(time*0.5);'#10 +
    '        vel.x = sin(p.y+time)*0.5; vel.y = sin(p.z+time*1.3)*0.5; vel.z = sin(p.x+time*0.7)*0.5;'#10 +
    '        pos += vel*deltaTime*timeScale*3.0;'#10 +
    '    } else if (mode == 4) {'#10 +
    '        float r = length(pos.xz); float ang = atan(pos.z,pos.x);'#10 +
    '        float sp = 1.5/sqrt(max(r,0.15)); ang += sp*deltaTime*timeScale*3.0;'#10 +
    '        pos.x = r*cos(ang); pos.z = r*sin(ang); pos.y = sin(r*6.0+time*2.0)*0.05;'#10 +
    '        vel = vec3(-sin(ang),0.0,cos(ang))*sp;'#10 +
    '    } else if (mode == 5) {'#10 +
    '        vel.y -= 3.0*deltaTime*timeScale; pos += vel*deltaTime*timeScale*5.0;'#10 +
    '        if (pos.y < -0.65 || length(pos) > 1.5) {'#10 +
    '            float a = rand(float(index)+time*0.13)*6.2831; float r2 = rand(float(index)*1.37+3.7)*0.05;'#10 +
    '            pos = vec3(cos(a)*r2, -0.55, sin(a)*r2); vel = vec3(cos(a)*0.8, 2.0+rand(float(index)*2.1)*0.5, sin(a)*0.8);'#10 +
    '        }'#10 +
    '        if (pos.y < -0.65 && vel.y < 0.0) { vel.y = abs(vel.y)*0.4; vel.x *= 0.7; vel.z *= 0.7; }'#10 +
    '    } else if (mode == 6) {'#10 +
    '        float r = length(pos.xz); float ang = atan(pos.z,pos.x);'#10 +
    '        float sp = 5.0/max(r,0.1); ang += sp*deltaTime*timeScale*3.0;'#10 +
    '        pos.x = r*cos(ang); pos.z = r*sin(ang); pos.y += sp*0.05*deltaTime*timeScale;'#10 +
    '        if (pos.y > 0.8) pos.y = -0.8;'#10 +
    '        vel = vec3(-sin(ang),sp*0.05,cos(ang))*sp;'#10 +
    '    } else if (mode == 7) {'#10 +
    '        float t = float(index)/float(particleCount); float strand = mod(float(index),2.0);'#10 +
    '        float ha = t*30.0*PI + strand*PI; float rad = 0.12; float y = (t-0.5)*2.4;'#10 +
    '        vec3 target = vec3(rad*cos(ha), y, rad*sin(ha));'#10 +
    '        float rot = time*0.5; float c = cos(rot); float s = sin(rot);'#10 +
    '        target = vec3(c*target.x-s*target.z, target.y, s*target.x+c*target.z);'#10 +
    '        pos = mix(pos, target, 0.03); vel = (target-pos)*5.0;'#10 +
    '    } else if (mode == 8) {'#10 +
    '        vec3 toC = -pos; float d = length(pos); float g = 2.0/max(d*d, 0.01);'#10 +
    '        vec3 gf = normalize(toC)*g; vec3 tan = cross(toC, vec3(0,1,0));'#10 +
    '        if (length(tan) > 0.001) tan = normalize(tan);'#10 +
    '        vel += (gf + tan*1.5)*deltaTime*timeScale; vel *= 0.98;'#10 +
    '        pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (d < 0.05) {'#10 +
    '            float a = rand(float(index)+time)*6.28; float r = 0.8+rand(float(index)*2.1)*0.2;'#10 +
    '            pos = vec3(cos(a)*r, (rand(float(index)*3.7)-0.5)*0.5, sin(a)*r); vel = vec3(0);'#10 +
    '        }'#10 +
    '    } else if (mode == 9) {'#10 +
    '        float ph = fract(time*0.2 + float(index)/float(particleCount)*0.1);'#10 +
    '        float rad = sin(ph*PI)*0.7;'#10 +
    '        vec3 dir = normalize(startPositions[index].xyz + vec3(0.001));'#10 +
    '        vec3 t = dir*rad; pos = mix(pos, t, 0.05); vel = (t-pos)*3.0;'#10 +
    '    } else if (mode == 10) {'#10 +
    '        vec3 p = pos*2.0;'#10 +
    '        float n1 = sin(p.x+time)*cos(p.y+time*0.7);'#10 +
    '        float n2 = sin(p.y+time*1.3)*cos(p.z+time*0.9);'#10 +
    '        float n3 = sin(p.z+time*0.7)*cos(p.x+time*1.1);'#10 +
    '        vel.x = n2-n3; vel.y = n3-n1; vel.z = n1-n2;'#10 +
    '        pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        pos = mod(pos+1.0, 2.0)-1.0;'#10 +
    '    } else if (mode == 11) {'#10 +
    '        // STICKMAN SCENE 3D - sun, house, trees, street, flowers, walking stickman'#10 +
    '        float r = float(index)/float(particleCount); vec3 t = vec3(0.0,-0.62,0.0);'#10 +
    '        float pc = float(particleCount);'#10 +
    '        float ps = clamp(sqrt(10000.0/max(pc,100.0)), 0.8, 5.0); // adaptive: few=big, many=small'#10 +
    '        float wx = sin(time*0.3)*0.4; float lp = sin(time*3.0)*0.12;'#10 +
    '        if (r < 0.04) {'#10 +
    '            // SUN - 3D sphere at top right with pulsing rays'#10 +
    '            float sr=(r/0.04)*6.2831+time*0.3; float rl=1.0+sin(sr*3.0+time*2.0)*0.25;'#10 +
    '            float sb=acos(2.0*rand(float(index)*1.3)-1.0);'#10 +
    '            t = vec3(0.7,0.65,0.0)+vec3(sin(sb)*cos(sr),sin(sb)*sin(sr),cos(sb))*0.12*rl*ps;'#10 +
    '        } else if (r < 0.14) {'#10 +
    '            // STICKMAN - deeper, head+body+arms+legs, walk cycle, slight Z wobble'#10 +
    '            float s=(r-0.04)/0.10; float zw=sin(time*2.0+float(index))*0.015;'#10 +
    '            if (s<0.12){float a=s/0.12*6.2831; t=vec3(wx,0.02,0.0)+vec3(cos(a),sin(a),zw)*0.05;}'#10 +
    '            else if (s<0.32){float b=(s-0.12)/0.20; t=vec3(wx,-0.15-b*0.15,zw*0.3);}'#10 +
    '            else if (s<0.52){float a=(s-0.32)/0.20; t=vec3(wx-0.04+lp*a,-0.15-a*0.10,zw*0.3);}'#10 +
    '            else if (s<0.72){float a=(s-0.52)/0.20; t=vec3(wx+0.04-lp*a,-0.15-a*0.10,zw*0.3);}'#10 +
    '            else if (s<0.86){float a=(s-0.72)/0.14; t=vec3(wx+lp*a*1.5,-0.30-a*0.18,zw*0.3);}'#10 +
    '            else {float a=(s-0.86)/0.14; t=vec3(wx-lp*a*1.5,-0.30-a*0.18,zw*0.3);}'#10 +
    '        } else if (r < 0.34) {'#10 +
    '            // HOUSE 3D - box body with Z depth + pyramid roof (roof starts at body top)'#10 +
    '            float h=(r-0.14)/0.20;'#10 +
    '            if (h<0.65){float bx=(rand(float(index)*1.1)-0.5)*0.25; float by=rand(float(index)*2.3)*0.30; float gz=(rand(float(index)*5.3)-0.5)*0.20*ps; t=vec3(-0.55+bx,-0.50+by,gz);}'#10 +
    '            else {float rt=(h-0.65)/0.35; float w=(1.0-rt)*0.15; float rx=(rand(float(index)*1.1)-0.5)*2.0*w; float rz=(rand(float(index)*3.1)-0.5)*2.0*w; t=vec3(-0.55+rx,-0.20+rt*0.15,rz);}'#10 +
    '        } else if (r < 0.49) {'#10 +
    '            // TREES 3D (2) - trunk with Z + foliage sphere'#10 +
    '            float tr=(r-0.34)/0.15;'#10 +
    '            if (tr<0.5){float t2=tr*2.0; if(t2<0.3) t=vec3(0.25,-0.52+t2*0.27,(rand(float(index)*2.1)-0.5)*0.04);'#10 +
    '            else {float a=rand(float(index)*1.1)*6.2831; float b=acos(2.0*rand(float(index)*2.3)-1.0); t=vec3(0.25+sin(b)*cos(a)*0.10*ps,-0.25+sin(b)*sin(a)*0.10*ps,cos(b)*0.10*ps);}}'#10 +
    '            else {float t2=(tr-0.5)*2.0; if(t2<0.3) t=vec3(0.55,-0.52+t2*0.22,(rand(float(index)*4.1)-0.5)*0.04);'#10 +
    '            else {float a=rand(float(index)*1.1)*6.2831; float b=acos(2.0*rand(float(index)*3.7)-1.0); t=vec3(0.55+sin(b)*cos(a)*0.08*ps,-0.30+sin(b)*sin(a)*0.08*ps,cos(b)*0.08*ps);}}'#10 +
    '        } else if (r < 0.59) {'#10 +
    '            // STREET 3D - has Z width, not just a flat line'#10 +
    '            float st=(r-0.49)/0.10; t=vec3(st*2.0-1.0,-0.60,(rand(float(index)*4.1)-0.5)*0.12);'#10 +
    '        } else if (r < 0.69) {'#10 +
    '            // FLOWERS 3D (3) - stem + petal sphere'#10 +
    '            float fr=(r-0.59)/0.10; float fx=-0.15+floor(fr*3.0)*0.25; float ft=mod(fr*3.0,1.0);'#10 +
    '            if (ft<0.4) t=vec3(fx,-0.55+ft*0.12,(rand(float(index)*6.1)-0.5)*0.03);'#10 +
    '            else {float a=rand(float(index)*1.1)*6.2831; float b=acos(2.0*rand(float(index)*6.7)-1.0); t=vec3(fx+sin(b)*cos(a)*0.035*ps,-0.43+sin(b)*sin(a)*0.035*ps,cos(b)*0.035*ps);}'#10 +
    '        } else {'#10 +
    '            // GOUND GRASS 3D - spread across X and Z, not just X'#10 +
    '            float gr=(r-0.69)/0.31; float gx=fract(gr*31.4159+rand(float(index)*1.1))*2.0-1.0; float gz=fract(gr*73.13+rand(float(index)*2.3))*2.0-1.0;'#10 +
    '            t=vec3(gx,-0.62+rand(float(index)*3.7)*0.04,gz);'#10 +
    '        }'#10 +
    '        // Fixed colors per element: 1=sun(yellow) 2=stickman(blue) 3=housebody(brown) 4=roof(red) 5=trees(green) 6=street(gray) 7=flowers(pink) 8=ground(dark green)'#10 +
    '        if (r<0.04) colorIdx=1.0; else if (r<0.14) colorIdx=2.0; else if (r<0.27) colorIdx=3.0; else if (r<0.34) colorIdx=4.0; else if (r<0.49) colorIdx=5.0; else if (r<0.59) colorIdx=6.0; else if (r<0.69) colorIdx=7.0; else colorIdx=8.0;'#10 +
    '        pos = mix(pos, t, 0.04); vel = (t-pos)*3.0;'#10 +
    '    } else if (mode == 12) {'#10 +
    '        // FOG - slow upward + lateral sin drift, wrap at edges.'#10 +
    '        vel.x = sin(time*0.5 + float(index)*0.1)*0.3;'#10 +
    '        vel.y = 0.2 + rand(float(index))*0.1;'#10 +
    '        vel.z = cos(time*0.4 + float(index)*0.13)*0.3;'#10 +
    '        pos += vel*deltaTime*timeScale*3.0;'#10 +
    '        if (pos.y > 1.0) pos.y = -1.0;'#10 +
    '        if (abs(pos.x) > 1.5) pos.x = -pos.x*0.9;'#10 +
    '        if (abs(pos.z) > 1.5) pos.z = -pos.z*0.9;'#10 +
    '    } else if (mode == 13) {'#10 +
    '        // FIRE - upward turbulent, fast rise, swirl'#10 +
    '        vel.x = sin(time*3.0 + float(index)*0.5 + pos.y*4.0)*1.5;'#10 +
    '        vel.y = 2.5 + rand(float(index))*1.0;'#10 +
    '        vel.z = cos(time*2.5 + float(index)*0.4 + pos.y*3.0)*1.5;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y > 1.0) { pos.y = -1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 14) {'#10 +
    '        // RAIN - gravity down, respawn at top'#10 +
    '        vel.y -= 15.0*deltaTime*timeScale;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y < -1.0) { pos.y = 1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; vel = vec3(0.0,-8.0,0.0); }'#10 +
    '    } else if (mode == 15) {'#10 +
    '        // SNOW - slow downward with sway'#10 +
    '        vel.x = sin(time + float(index)*0.3)*0.5;'#10 +
    '        vel.y = -0.8;'#10 +
    '        vel.z = cos(time*0.7 + float(index)*0.2)*0.5;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y < -1.0) { pos.y = 1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 16) {'#10 +
    '        // SMOKE - upward expanding, slow fade'#10 +
    '        vel.x = sin(time*0.5 + float(index)*0.2)*0.3;'#10 +
    '        vel.y = 0.8 + rand(float(index))*0.4;'#10 +
    '        vel.z = cos(time*0.4 + float(index)*0.3)*0.3;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y > 1.0) { pos.y = -1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 17) {'#10 +
    '        // EXPLOSION - outward burst + gravity, one-shot feel'#10 +
    '        vec3 from_center = pos;'#10 +
    '        if (length(from_center) > 0.001) vel += normalize(from_center)*2.0*deltaTime;'#10 +
    '        vel.y -= 5.0*deltaTime*timeScale;'#10 +
    '        vel *= 0.98;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (length(pos) > 2.0) { pos = vec3(0.0); vel = normalize(vec3(rand(float(index))-0.5, rand(float(index)*1.3)-0.5, rand(float(index)*2.1)-0.5))*3.0; }'#10 +
    '    } else if (mode == 18) {'#10 +
    '        // SPARKS - fast outward + gravity, short bursts'#10 +
    '        vec3 from_center = pos;'#10 +
    '        if (length(from_center) > 0.001) vel += normalize(from_center)*8.0*deltaTime;'#10 +
    '        vel.y -= 12.0*deltaTime*timeScale;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (length(pos) > 2.0 || pos.y < -1.0) { pos = vec3(0.0); vel = normalize(vec3(rand(float(index))-0.5, abs(rand(float(index)*1.3)), rand(float(index)*2.1)-0.5))*5.0; }'#10 +
    '    } else if (mode == 19) {'#10 +
    '        // FOUNTAIN2 - gravity + respawn at origin'#10 +
    '        vel.y -= 9.81*deltaTime*timeScale;'#10 +
    '        pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (pos.y < -1.0) { pos = vec3(0.0); vel = vec3(rand(float(index))-0.5, 5.0+rand(float(index))*2.0, rand(float(index)*1.3)-0.5); }'#10 +
    '    } else if (mode == 20) {'#10 +
    '        // STORM - chaotic 3D flow field, region wrap'#10 +
    '        vec3 p = pos*0.5 + vec3(time*0.2);'#10 +
    '        vel.x = sin(p.y*2.0 + time)*5.0;'#10 +
    '        vel.y = sin(p.z*1.7 + time*1.3)*2.0;'#10 +
    '        vel.z = cos(p.x*2.1 + time*0.7)*5.0;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.x < -1.0) pos.x = 1.0; if (pos.x > 1.0) pos.x = -1.0;'#10 +
    '        if (pos.y < -1.0) pos.y = 1.0; if (pos.y > 1.0) pos.y = -1.0;'#10 +
    '        if (pos.z < -1.0) pos.z = 1.0; if (pos.z > 1.0) pos.z = -1.0;'#10 +
    '    } else if (mode == 21) {'#10 +
    '        // DUST - slow drifting fine particles'#10 +
    '        vel.x = sin(time*0.2 + float(index)*0.5)*0.2;'#10 +
    '        vel.y = cos(time*0.15 + float(index)*0.3)*0.1;'#10 +
    '        vel.z = sin(time*0.18 + float(index)*0.4)*0.2;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.x < -1.0) pos.x = 1.0; if (pos.x > 1.0) pos.x = -1.0;'#10 +
    '        if (pos.y < -1.0) pos.y = 1.0; if (pos.y > 1.0) pos.y = -1.0;'#10 +
    '        if (pos.z < -1.0) pos.z = 1.0; if (pos.z > 1.0) pos.z = -1.0;'#10 +
    '    } else if (mode == 22) {'#10 +
    '        // ANTS - ground-level random walk, stay near Y=-0.8'#10 +
    '        float ph = sin(pos.x*0.5 + pos.z*0.5 + time);'#10 +
    '        vel.x = sin(float(index)*1.7 + time*2.0 + ph*3.0)*1.5;'#10 +
    '        vel.z = cos(float(index)*2.3 + time*1.5 + ph*2.0)*1.5;'#10 +
    '        vel.y = 0.0;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        pos.y = -0.8;'#10 +
    '        if (pos.x < -1.0) pos.x = 1.0; if (pos.x > 1.0) pos.x = -1.0;'#10 +
    '        if (pos.z < -1.0) pos.z = 1.0; if (pos.z > 1.0) pos.z = -1.0;'#10 +
    '    } else if (mode == 23) {'#10 +
    '        // BLACK GOO - viscous dripping, gravity + moderate drag'#10 +
    '        vel.y -= 6.0*deltaTime*timeScale;'#10 +
    '        vel *= 0.99;'#10 +
    '        pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (pos.y < -1.0) { pos.y = 1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; vel = vec3(0.0, -0.5, 0.0); }'#10 +
    '    } else if (mode == 24) {'#10 +
    '        // BUBBLES - upward wobble, wrap at top'#10 +
    '        vel.y = 1.0 + sin(time*2.0+float(index)*0.5)*0.3;'#10 +
    '        vel.x = sin(time+float(index)*0.7)*0.2;'#10 +
    '        vel.z = cos(time*0.9+float(index)*0.4)*0.2;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y > 1.0) { pos.y = -1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 25) {'#10 +
    '        // FIREFLIES - slow random walk with glow pulse (color pulse via velocity)'#10 +
    '        vel.x = sin(time*0.7+float(index)*1.3)*0.5;'#10 +
    '        vel.y = cos(time*0.5+float(index)*0.9)*0.5;'#10 +
    '        vel.z = sin(time*0.6+float(index)*1.7)*0.5;'#10 +
    '        pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (abs(pos.x) > 1.5) pos.x = -pos.x*0.9;'#10 +
    '        if (abs(pos.y) > 1.5) pos.y = -pos.y*0.9;'#10 +
    '        if (abs(pos.z) > 1.5) pos.z = -pos.z*0.9;'#10 +
    '    } else if (mode == 26) {'#10 +
    '        // LEAVES - falling with rotation/sway'#10 +
    '        vel.x = sin(time*0.8+float(index)*0.5)*1.5;'#10 +
    '        vel.y = -1.0;'#10 +
    '        vel.z = cos(time*0.6+float(index)*0.3)*1.5;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y < -1.0) { pos.y = 1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 27) {'#10 +
    '        // ENERGY - field crackle around center, pulse'#10 +
    '        vec3 nz = vec3(sin(pos.x*5.0+time*10.0), sin(pos.y*5.0+time*8.0), sin(pos.z*5.0+time*9.0));'#10 +
    '        vel += nz*3.0*deltaTime;'#10 +
    '        vec3 tc = vec3(0.0) - pos; vel += normalize(tc)*0.5*deltaTime;'#10 +
    '        vel *= 0.9;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (length(pos) > 2.0) pos = normalize(pos)*1.5;'#10 +
    '    } else if (mode == 28) {'#10 +
    '        // PLASMA - chaotic electric motion with noise + radial pull'#10 +
    '        vec3 tc = vec3(0.0) - pos; float d = length(tc);'#10 +
    '        vec3 noise = vec3(rand(float(index)+time)-0.5, rand(float(index)*1.3+time)-0.5, rand(float(index)*2.1+time)-0.5);'#10 +
    '        if (d > 0.001) { vec3 rad = normalize(tc); vec3 tan = cross(rad, vec3(0,1,0)); vel += (rad*sin(time*8.0+d*5.0) + tan*cos(time*6.0+d*3.0) + noise*4.0)*3.0*deltaTime; }'#10 +
    '        vel *= 0.95; pos += vel*deltaTime*timeScale;'#10 +
    '        if (length(pos) > 2.0) pos = normalize(pos)*1.5;'#10 +
    '    } else if (mode == 29) {'#10 +
    '        // LIGHTNING - jagged fast random walk + strobe pulse (via velocity)'#10 +
    '        vel.x = (rand(float(index)+time)-0.5)*8.0;'#10 +
    '        vel.y = -2.0;'#10 +
    '        vel.z = (rand(float(index)*1.3+time)-0.5)*8.0;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y < -1.0) { pos.y = 1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 30) {'#10 +
    '        // ASH - slow falling embers, color shift via velocity direction'#10 +
    '        vel.x = sin(time*0.5+float(index)*0.3)*0.8;'#10 +
    '        vel.y = -0.5 - rand(float(index))*0.5;'#10 +
    '        vel.z = cos(time*0.4+float(index)*0.5)*0.8;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y < -1.0) { pos.y = 1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 31) {'#10 +
    '        // DEBRIS - outward explosion with rotation (size varies via velocity)'#10 +
    '        vec3 fc = pos; if (length(fc) > 0.001) vel += normalize(fc)*1.0*deltaTime;'#10 +
    '        vel.y -= 8.0*deltaTime*timeScale; vel *= 0.98;'#10 +
    '        pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (length(pos) > 2.0) { pos = vec3(0.0); vel = normalize(vec3(rand(float(index))-0.5, rand(float(index)*1.3), rand(float(index)*2.1)-0.5))*4.0; }'#10 +
    '    } else if (mode == 32) {'#10 +
    '        // STEAM - hot vapor rising, expanding, drift'#10 +
    '        vel.x = sin(time*0.6+float(index)*0.3)*0.5;'#10 +
    '        vel.y = 1.5 + rand(float(index))*0.5;'#10 +
    '        vel.z = cos(time*0.5+float(index)*0.4)*0.5;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y > 1.0) { pos.y = -1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 33) {'#10 +
    '        // SNOW DRIFT - snow falls and accumulates on ground (Y=-1.0), stays frozen'#10 +
    '        if (pos.y > -1.0) {'#10 +
    '            vel.x = sin(time*0.5 + float(index)*0.3)*0.5;'#10 +
    '            vel.y = -0.4;'#10 +
    '            vel.z = cos(time*0.4 + float(index)*0.2)*0.5;'#10 +
    '            pos += vel*deltaTime*timeScale;'#10 +
    '            if (pos.y < -1.0) pos.y = -1.0;'#10 +
    '        } else {'#10 +
    '            // Already on ground - frozen, no movement'#10 +
    '            vel = vec3(0.0);'#10 +
    '            pos.y = -1.0;'#10 +
    '        }'#10 +
    '    } else if (mode == 34) {'#10 +
    '        // INSECTS - 3D flight with wing flutter + swarm centering'#10 +
    '        vec3 swirl = vec3(sin(time*5.0+float(index)*0.3), cos(time*4.0+float(index)*0.5), sin(time*4.5+float(index)*0.4));'#10 +
    '        vec3 tc = vec3(0.0) - pos; vel += tc*0.3*deltaTime + swirl*2.0*deltaTime; vel *= 0.95;'#10 +
    '        pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (abs(pos.x) > 1.5) pos.x = -pos.x*0.9; if (abs(pos.z) > 1.5) pos.z = -pos.z*0.9;'#10 +
    '    } else if (mode == 35) {'#10 +
    '        // SWARM - boids-like centering + wander around origin'#10 +
    '        vec3 tc = vec3(0.0) - pos; float d = length(tc);'#10 +
    '        vec3 w = vec3(sin(time+float(index)*0.5), cos(time*1.3+float(index)*0.3), sin(time*0.7+float(index)*0.9));'#10 +
    '        vel += w*0.5*deltaTime + normalize(tc)*0.3*deltaTime; if (d > 1.0) vel += normalize(tc)*2.0*deltaTime;'#10 +
    '        vel *= 0.97; pos += vel*deltaTime*timeScale*2.0;'#10 +
    '    } else if (mode == 36) {'#10 +
    '        // BEAM - sparkle shower falling from top'#10 +
    '        vel.y = -3.0 - rand(float(index))*2.0; vel.x = sin(time*10.0+float(index))*0.5; vel.z = cos(time*8.0+float(index))*0.5;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y < -1.0) { pos.y = 1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 37) {'#10 +
    '        // PORTAL - swirling disc in XZ plane around origin'#10 +
    '        vec3 tc = vec3(0.0) - pos; tc.y = 0.0; float r = length(tc);'#10 +
    '        float ang = atan(pos.z, pos.x); float sp = 4.0/max(r, 0.2); ang += sp*deltaTime*timeScale;'#10 +
    '        pos.x = r*cos(ang); pos.z = r*sin(ang); pos.y = sin(time*2.0+float(index))*0.1;'#10 +
    '        vel = vec3(-sin(ang), 0.0, cos(ang))*sp;'#10 +
    '    } else if (mode == 38) {'#10 +
    '        // CRYSTAL GROWTH - particles drift inward then freeze at radius'#10 +
    '        vec3 tc = vec3(0.0) - pos; float d = length(tc);'#10 +
    '        if (d > 0.5) vel = normalize(tc)*0.5; else vel = vec3(0.0); pos += vel*deltaTime*timeScale;'#10 +
    '        if (d < 0.52) pos = normalize(pos)*0.5;'#10 +
    '    } else if (mode == 39) {'#10 +
    '        // PIXIE DUST - magical sparkle trail with sharp pulses'#10 +
    '        vec3 w = vec3(sin(time*2.0+float(index)*1.7), cos(time*1.5+float(index)*1.3), sin(time*1.8+float(index)*1.1));'#10 +
    '        vel += w*1.0*deltaTime; vel *= 0.96; pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (abs(pos.x) > 1.5) pos.x = -pos.x*0.9; if (abs(pos.y) > 1.5) pos.y = -pos.y*0.9; if (abs(pos.z) > 1.5) pos.z = -pos.z*0.9;'#10 +
    '    } else if (mode == 40) {'#10 +
    '        // GHOST MIST - translucent drifting, region wrap, slow'#10 +
    '        vel.x = sin(time*0.3+float(index)*0.7)*0.3; vel.y = sin(time*0.2+float(index)*0.5+pos.x*0.3)*0.2; vel.z = cos(time*0.25+float(index)*0.6)*0.3;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.x < -1.0) pos.x = 1.0; if (pos.x > 1.0) pos.x = -1.0; if (pos.z < -1.0) pos.z = 1.0; if (pos.z > 1.0) pos.z = -1.0;'#10 +
    '    } else if (mode == 41) {'#10 +
    '        // COMET - particles drift toward origin from far away'#10 +
    '        vec3 tc = vec3(0.0) - pos; float d = length(tc);'#10 +
    '        if (d > 0.001) vel = normalize(tc)*1.0; pos += vel*deltaTime*timeScale;'#10 +
    '        if (d < 0.1) { pos = vec3(rand(float(index)+time)*3.0-1.5, rand(float(index)*1.3)*3.0-1.5, rand(float(index)*2.1+time)*3.0-1.5); vel = vec3(0.0); }'#10 +
    '    } else if (mode == 42) {'#10 +
    '        // SHOCKWAVE RING - rapidly expanding ring on ground, respawn at center'#10 +
    '        vec3 tc = vec3(0.0) - pos; tc.y = 0.0; float r = length(tc);'#10 +
    '        float ang = atan(pos.z, pos.x); r += 5.0*deltaTime*timeScale;'#10 +
    '        pos.x = r*cos(ang); pos.z = r*sin(ang); pos.y = -0.9;'#10 +
    '        if (r > 2.0) { r = 0.1; pos = vec3(0.1*cos(ang), -0.9, 0.1*sin(ang)); }'#10 +
    '    } else if (mode == 43) {'#10 +
    '        // RAIN SPLASH - particles bounce up from ground then fall back'#10 +
    '        vel.y -= 10.0*deltaTime*timeScale; pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y < -1.0) { float a = rand(float(index)+time)*6.2831; vel = vec3(cos(a)*2.0, 2.0+rand(float(index))*1.0, sin(a)*2.0); pos.y = -1.0; }'#10 +
    '    } else if (mode == 44) {'#10 +
    '        // LAVA BUBBLE - bubbling upward, pop at top, respawn at bottom'#10 +
    '        vel.y = 0.5 + rand(float(index))*0.3; vel.x = sin(time*2.0+float(index))*0.1; vel.z = cos(time*1.8+float(index))*0.1;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y > 0.5) { pos.y = -1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 45) {'#10 +
    '        // STAR FIELD - twinkling stars, very slow drift, region wrap'#10 +
    '        vel.x = sin(time*0.05+float(index))*0.05; vel.y = cos(time*0.04+float(index)*0.7)*0.05; vel.z = sin(time*0.06+float(index)*0.3)*0.05;'#10 +
    '        pos += vel*deltaTime;'#10 +
    '        if (pos.x < -1.0) pos.x = 1.0; if (pos.x > 1.0) pos.x = -1.0; if (pos.y < -1.0) pos.y = 1.0; if (pos.y > 1.0) pos.y = -1.0; if (pos.z < -1.0) pos.z = 1.0; if (pos.z > 1.0) pos.z = -1.0;'#10 +
    '    } else if (mode == 46) {'#10 +
    '        // NEBULA - slow drifting cloud with wave-modulated motion, region wrap'#10 +
    '        vel.x = sin(pos.x*0.3+time*0.1)*0.3 + sin(time*0.2+float(index)*0.1)*0.1;'#10 +
    '        vel.y = sin(pos.y*0.3+time*0.08)*0.2;'#10 +
    '        vel.z = cos(pos.z*0.3+time*0.09)*0.3 + cos(time*0.15+float(index)*0.15)*0.1;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.x < -1.0) pos.x = 1.0; if (pos.x > 1.0) pos.x = -1.0; if (pos.y < -1.0) pos.y = 1.0; if (pos.y > 1.0) pos.y = -1.0; if (pos.z < -1.0) pos.z = 1.0; if (pos.z > 1.0) pos.z = -1.0;'#10 +
    '    } else if (mode == 47) {'#10 +
    '        // TORNADO - 3D rotating vortex, wider funnel, shorter height'#10 +
    '        vec3 tc = vec3(0.0) - pos; tc.y = 0.0; float r = length(tc); float ang = atan(pos.z, pos.x);'#10 +
    '        float sp = 6.0/max(r, 0.3); ang += sp*deltaTime*timeScale;'#10 +
    '        float heightFrac = (pos.y + 1.0) * 0.5; float funnel = 0.7 + heightFrac*0.3;'#10 +
    '        pos.x = r*funnel*cos(ang); pos.z = r*funnel*sin(ang); pos.y += (1.2+r*0.2)*deltaTime*timeScale;'#10 +
    '        if (pos.y > 0.6) { float a2 = rand(float(index)+time)*6.2831; float r2 = rand(float(index)*1.7+time)*1.2; pos = vec3(cos(a2)*r2, -1.0, sin(a2)*r2); }'#10 +
    '        vel = vec3(-sin(ang), 1.5, cos(ang))*sp;'#10 +
    '    } else if (mode == 48) {'#10 +
    '        // GLOW - pulsing radial light halo around origin, slow drift outward + pull back'#10 +
    '        vec3 tc = vec3(0.0) - pos; float d = length(tc); if (d > 0.001) vel += normalize(tc)*0.5*deltaTime; vel *= 0.95; pos += vel*deltaTime*timeScale;'#10 +
    '        if (length(pos) > 1.5) pos = normalize(pos)*1.5;'#10 +
    '    } else if (mode == 49) {'#10 +
    '        // VOLUMETRIC LIGHT - god rays shimmer, upward beam'#10 +
    '        vec3 to_origin = vec3(0.0) - pos; float d = length(to_origin);'#10 +
    '        vec3 outward = vec3(0.0); if (d > 0.001) outward = normalize(to_origin)*-1.0;'#10 +
    '        vel = outward*0.3 + vec3(0.0, 0.6, 0.0); pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y > 1.0) { pos.y = -1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 50) {'#10 +
    '        // SANDSTORM - fast horizontal wind, region wrap'#10 +
    '        vel.x = 8.0 + sin(time*0.5+pos.y*0.3)*2.0; vel.y = sin(time+float(index))*0.3; vel.z = cos(time*0.5+float(index))*0.5;'#10 +
    '        pos += vel*deltaTime*timeScale; if (pos.x > 1.0) pos.x = -1.0;'#10 +
    '    } else if (mode == 51) {'#10 +
    '        // HAILSTORM - heavy ice balls with bounce on ground'#10 +
    '        vel.y -= 18.0*deltaTime*timeScale; vel.x = sin(time+float(index)*0.3)*0.3; pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y < -1.0) { pos.y = -1.0; vel.y = abs(vel.y)*0.4; if (abs(vel.y) < 1.0) { pos.y = 1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; vel = vec3(0.0,-2.0,0.0); } }'#10 +
    '    } else if (mode == 52) {'#10 +
    '        // WHIRPOOL - water vortex spiral inward in XZ plane'#10 +
    '        vec3 tc = vec3(0.0) - pos; tc.y = 0.0; float r = length(tc); float ang = atan(pos.z, pos.x);'#10 +
    '        float sp = 3.0/max(r, 0.2); ang += sp*deltaTime*timeScale; r -= 0.3*deltaTime*timeScale;'#10 +
    '        if (r < 0.1) { r = 1.0+rand(float(index)+time)*0.5; ang = rand(float(index)*1.7+time)*6.2831; }'#10 +
    '        pos.x = r*cos(ang); pos.z = r*sin(ang); pos.y = -0.5 + sin(time*2.0+r*5.0)*0.05;'#10 +
    '    } else if (mode == 53) {'#10 +
    '        // MUSHROOM CLOUD - burst outward, rise, then cap spreads at top'#10 +
    '        float dist = length(pos);'#10 +
    '        float y = pos.y;'#10 +
    '        if (y < 0.3) {'#10 +
    '            // Rising column: particles go straight up, slight outward push'#10 +
    '            vel.y = 1.5 + rand(float(index))*0.5;'#10 +
    '            vec3 fc = pos; fc.y = 0.0; if (length(fc) > 0.001) vel += normalize(fc)*0.3*deltaTime;'#10 +
    '        } else {'#10 +
    '            // Cap: spread outward + slow rise, curl back down at edges'#10 +
    '            vec3 fc = pos; fc.y = 0.0; if (length(fc) > 0.001) vel += normalize(fc)*1.5*deltaTime;'#10 +
    '            vel.y = 0.3; if (length(fc) > 0.6) vel.y -= 0.5;'#10 +
    '        }'#10 +
    '        vel *= 0.97; pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (pos.y > 1.0 || length(pos) > 2.0) { pos = vec3(rand(float(index))-0.5, -1.0, rand(float(index)*1.3)-0.5)*0.3; vel = vec3(0.0, 1.0, 0.0); }'#10 +
    '    } else if (mode == 54) {'#10 +
    '        // SMOKE COLUMN - vertical stream with lateral wobble, respawn at bottom'#10 +
    '        vel.y = 1.5 + rand(float(index))*0.5; vel.x = sin(time*0.5+float(index)*0.3+pos.y*0.3)*0.5; vel.z = cos(time*0.4+float(index)*0.2+pos.y*0.2)*0.5;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y > 1.0) { pos.y = -1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 55) {'#10 +
    '        // BLACK SMOKE - heavy dark slow-rising smoke, dense and slow'#10 +
    '        vel.y = 0.3 + rand(float(index))*0.2; vel.x = sin(time*0.3+float(index)*0.5)*0.15; vel.z = cos(time*0.2+float(index)*0.4)*0.15;'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        if (pos.y > 1.0) { pos.y = -1.0; pos.x = rand(float(index)+time)*2.0-1.0; pos.z = rand(float(index)*1.3+time)*2.0-1.0; }'#10 +
    '    } else if (mode == 56) {'#10 +
    '        // ENGINE EXHAUST - thick short burst, dissipates outward and fades'#10 +
    '        vec3 dir = vec3(0.0, 0.0, 1.0);'#10 +
    '        float dist = max(pos.z, 0.0);'#10 +
    '        float spread = 0.1 + dist*1.2;'#10 +
    '        vec3 right_v = vec3(1.0, 0.0, 0.0); vec3 up_v = vec3(0.0, 1.0, 0.0);'#10 +
    '        float ang = rand(float(index)+time)*6.2831;'#10 +
    '        float rad = rand(float(index)*1.3)*spread;'#10 +
    '        float speed = max(4.0 - dist*6.0, 0.2);'#10 +
    '        vec3 offset = (right_v*cos(ang) + up_v*sin(ang))*rad*2.5;'#10 +
    '        vel = dir*speed + offset;'#10 +
    '        vel += vec3(rand(float(index)*3.7+time)-0.5, rand(float(index)*4.1+time)-0.5, rand(float(index)*5.3+time)-0.5)*dist*0.8;'#10 +
    '        pos += vel*deltaTime*timeScale*2.0;'#10 +
    '        if (pos.z > 0.5 || length(vec3(pos.x, pos.y, 0.0)) > 0.5) { pos = vec3(0.0); vel = vec3(0.0); }'#10 +
    '    } else if (mode == 57) {'#10 +
    '        // SPARK TRAIL - sparkler-style spark trail with flicker, gravity'#10 +
    '        vec3 from_origin = pos; if (length(from_origin) > 0.001) vel += normalize(from_origin)*2.0*deltaTime;'#10 +
    '        vel.y -= 5.0*deltaTime*timeScale; vel.x += sin(time*20.0+float(index))*0.5*deltaTime; vel.z += cos(time*18.0+float(index))*0.5*deltaTime;'#10 +
    '        pos += vel*deltaTime*timeScale; if (length(pos) > 2.0) { pos = vec3(0.0); vel = normalize(vec3(rand(float(index))-0.5, abs(rand(float(index)*1.3)), rand(float(index)*2.1)-0.5))*5.0; }'#10 +
    '    } else if (mode == 58) {'#10 +
    '        // MAGIC MISSILE - projectile moving forward with trailing spiral behind it'#10 +
    '        float t = fract(time*0.3 + float(index)/float(particleCount)); // 0..1 cycle'#10 +
    '        float zPos = t*2.0 - 1.0; // moves from -1 to +1 along Z'#10 +
    '        float trailOffset = (1.0-t)*0.5; // trail spreads behind the head'#10 +
    '        float ang = time*10.0 + float(index)*0.3;'#10 +
    '        float rad = trailOffset + 0.05;'#10 +
    '        vec3 target_pos = vec3(cos(ang)*rad, sin(ang)*rad, zPos - trailOffset*2.0);'#10 +
    '        pos = mix(pos, target_pos, 0.15); vel = (target_pos - pos)*5.0;'#10 +
    '    } else if (mode == 59) {'#10 +
    '        // CLOUDS - Curl Noise: divergenzfreies Wirbel-Rauschen, kein Zusammenballen'#10 +
    '        // Partikel flieen umeinander herum wie echter Wasserdampf/Rauch.'#10 +
    '        vec3 p = pos * 1.8; // Skalierung der Wolkenstrukturen'#10 +
    '        float t = time * 0.15; // Geschwindigkeit der inneren Verformung'#10 +
    '        float e = 0.008; // Schrittweite fuer numerische Ableitung (Finite Differences)'#10 +
    '        // Prozedurale 3D-Rausch-Funktion (Layered Sines + Rotation fuer Pseudo-Noise)'#10 +
    '        // Erzeugt ein unkorreliertes Feld fuer das Vektor-Potential A'#10 +
    '        #define NOISE3D(q) (sin((q).x + t) * cos((q).y - t * 0.7) * sin((q).z + t * 0.3) + sin((q).y * 2.1 + t * 1.3) * cos((q).z * 1.7 - t) * sin((q).x * 1.5 + t * 0.5) * 0.5)'#10 +
    '        // Numerische Rotation (Curl) berechnen: v = nabla x A'#10 +
    '        float ax_dy = NOISE3D(p+vec3(0.0,e,0.0)) - NOISE3D(p-vec3(0.0,e,0.0));'#10 +
    '        float ax_dz = NOISE3D(p+vec3(0.0,0.0,e)) - NOISE3D(p-vec3(0.0,0.0,e));'#10 +
    '        float ay_dx = NOISE3D(p+vec3(e,0.0,0.0)) - NOISE3D(p-vec3(e,0.0,0.0));'#10 +
    '        float ay_dz = NOISE3D(p+vec3(0.0,0.0,e)) - NOISE3D(p-vec3(0.0,0.0,e));'#10 +
    '        float az_dx = NOISE3D(p+vec3(e,0.0,0.0)) - NOISE3D(p-vec3(e,0.0,0.0));'#10 +
    '        float az_dy = NOISE3D(p+vec3(0.0,e,0.0)) - NOISE3D(p-vec3(0.0,e,0.0));'#10 +
    '        // Curl-Vektor: divergenzfreies Geschwindigkeitsfeld'#10 +
    '        vec3 curl;'#10 +
    '        curl.x = az_dy - ay_dz;'#10 +
    '        curl.y = ax_dz - az_dx;'#10 +
    '        curl.z = ay_dx - ax_dy;'#10 +
    '        float cl = length(curl); if (cl > 0.001) curl = normalize(curl) * (cl / (2.0*e));'#10 +
    '        // Globale Drift (Wind) damit die Wolke wandert'#10 +
    '        vec3 drift = vec3(0.12, 0.02, -0.05);'#10 +
    '        // Geschwindigkeit zuweisen und Position updaten'#10 +
    '        vel = mix(vel, curl*1.5 + drift, 0.1);'#10 +
    '        pos += vel*deltaTime*timeScale;'#10 +
    '        // Bounding Box mit Wrap: Partikel die ausbrechen spawnen auf der Gegenseite'#10 +
    '        float bounds = 1.4;'#10 +
    '        if (pos.x > bounds) { pos.x = -bounds; pos.y = (fract(float(index)*0.13)*2.0-1.0)*0.5; }'#10 +
    '        if (pos.x < -bounds) { pos.x = bounds; pos.y = (fract(float(index)*0.13)*2.0-1.0)*0.5; }'#10 +
    '        if (pos.y > 0.8) pos.y = -0.2;'#10 +
    '        if (pos.y < -0.4) pos.y = 0.6;'#10 +
    '        if (pos.z > bounds) pos.z = -bounds;'#10 +
    '        if (pos.z < -bounds) pos.z = bounds;'#10 +
    '    }'#10 +
    '    // Emitter modes (12+) use colorIdx=100 to signal custom color to vertex shader.'#10 +
    '    if (mode >= 12) colorIdx = 100.0;'#10 +
    '    // Global forces (applied to ALL modes after per-type behavior)'#10 +
    '    vel += globalWind * deltaTime;'#10 +
    '    vel -= globalGravity * deltaTime;'#10 +
    '    if (pushActive != 0) {'#10 +
    '        vec3 toP = pos - pushPos; float d = length(toP);'#10 +
    '        if (d < pushRadius && d > 0.001) {'#10 +
    '            vel += normalize(toP) * pushStrength * (1.0 - d/pushRadius);'#10 +
    '        }'#10 +
    '    }'#10 +
    '    positions[index] = vec4(pos, colorIdx);'#10 +
    '    velocities[index].xyz = vel;'#10 +
    '}';

  VERTEX_SHADER_SRC: AnsiString =
    '#version 430'#10 +
    'layout (location=0) in vec3 vertexPosition;'#10 +
    'layout (location=0) uniform mat4 projectionMatrix;'#10 +
    'layout (location=1) uniform mat4 viewMatrix;'#10 +
    'layout (location=2) uniform float particleScale;'#10 +
    'layout (location=3) uniform float emColorR;'#10 +
    'layout (location=4) uniform float emColorG;'#10 +
    'layout (location=5) uniform float emColorB;'#10 +
    'layout (location=6) uniform float emColorA;'#10 +
    'layout (location=7) uniform float emSize;'#10 +
    'layout (location=8) uniform float hdrMultiplier;'#10 +
    'layout(std430, binding=0) buffer ssbo0 { vec4 positions[]; };'#10 +
    'layout(std430, binding=1) buffer ssbo1 { vec4 velocities[]; };'#10 +
    'out vec4 fragColor;'#10 +
    'void main() {'#10 +
    '    vec3 velocity = velocities[gl_InstanceID].xyz;'#10 +
    '    vec4 posData = positions[gl_InstanceID];'#10 +
    '    vec3 position = posData.xyz; float ci = posData.w;'#10 +
    '    if (ci >= 100.0) {'#10 +
    '        // Emitter mode: use custom color from uniforms (set by host)'#10 +
    '        fragColor = vec4(emColorR, emColorG, emColorB, emColorA) * vec4(hdrMultiplier, hdrMultiplier, hdrMultiplier, 1.0);'#10 +
    '    } else if (ci > 0.5) {'#10 +
    '        // Fixed colors: 1=sun(yellow) 2=stickman(blue) 3=housebody(brown) 4=roof(red) 5=trees(green) 6=street(gray) 7=flowers(pink) 8=ground(darkgreen)'#10 +
    '        if (ci<1.5) fragColor=vec4(1.0,0.8,0.0,1.0);'#10 +
    '        else if (ci<2.5) fragColor=vec4(0.2,0.5,1.0,1.0);'#10 +
    '        else if (ci<3.5) fragColor=vec4(0.8,0.6,0.4,1.0);'#10 +
    '        else if (ci<4.5) fragColor=vec4(0.9,0.15,0.1,1.0);'#10 +
    '        else if (ci<5.5) fragColor=vec4(0.15,0.7,0.15,1.0);'#10 +
    '        else if (ci<6.5) fragColor=vec4(0.4,0.4,0.4,1.0);'#10 +
    '        else if (ci<7.5) fragColor=vec4(1.0,0.3,0.7,1.0);'#10 +
    '        else fragColor=vec4(0.1,0.5,0.05,1.0);'#10 +
    '    } else {'#10 +
    '        fragColor.rgb = abs(normalize(velocity)) + 0.2; fragColor.a = 1.0;'#10 +
    '    }'#10 +
    '    float scale = (ci >= 100.0) ? 0.01*particleScale*emSize : 0.005*particleScale;'#10 +
    '    vec3 vertexView = vertexPosition*scale;'#10 +
    '    vec2 vv = (viewMatrix*vec4(velocity,0)).xy;'#10 +
    '    float va = atan(vv.y, vv.x); float sp = length(vv);'#10 +
    '    float rot = va - radians(90);'#10 +
    '    vec2 xv = vec2(cos(rot),sin(rot)); vec2 yv = vec2(-sin(rot),cos(rot));'#10 +
    '    vertexView.xy = vertexView.x*xv + vertexView.y*yv;'#10 +
    '    float isTip = float(gl_VertexID == 2); float al = sp*0.05;'#10 +
    '    vertexView.xy = vertexView.xy*(1-isTip) + isTip*vertexView.xy*(al+1);'#10 +
    '    vertexView += (viewMatrix*vec4(position,1)).xyz;'#10 +
    '    gl_Position = projectionMatrix*vec4(vertexView,1);'#10 +
    '}';

  FRAGMENT_SHADER_SRC: AnsiString =
    '#version 430'#10 +
    'in vec4 fragColor; out vec4 finalColor;'#10 +
    'void main() { finalColor = fragColor; }';

  PARTICLE_VERTS: array[0..2] of TVector3 = (
    (x: -0.86; y: -0.5; z: 0.0), (x: 0.86; y: -0.5; z: 0.0), (x: 0.0; y: 1.0; z: 0.0));

{ ========================================================================== }
{ TYutaniParticleEngine                                                      }
{ ========================================================================== }

constructor TYutaniParticleEngine.Create(ANumParticles: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  if ANumParticles < 1024 then ANumParticles := 1024;
  FNumParticles := ((ANumParticles + 1023) div 1024) * 1024;
  FComputeProgram := 0; FRenderProgram := 0;
  FSSBO_Positions := 0; FSSBO_Velocities := 0; FSSBO_StartPositions := 0;
  FBillboardVAO := 0; FBillboardVBO := 0;
  FParticleScale := 1.0; FTimeScale := 0.2; FSigma := 10.0;
  FRho := 28.0; FBeta := 8.0/3.0; FTime := 0.0;
  FInstancesX1000 := 1000.0; { Default: show ALL particles }
  FMode := 0; FNeedsReset := True;
  FPushPos := Vector3Create(0, 0, 0); FPushRadius := 0.3; FPushStrength := 8.0;
  FPushActive := False;
  FGPUInitialized := False;
  FEmColorR := 1.0; FEmColorG := 0.55; FEmColorB := 0.08; FEmColorA := 0.8;
  FEmSize := 0.1;
  FGlobalWind := Vector3Create(0, 0, 0);
  FGlobalGravity := Vector3Create(0, 0, 0);
  FHDRMultiplier := 1.0;
end;

destructor TYutaniParticleEngine.Destroy;
begin
  FreeGPUResources; FLock.Free; inherited;
end;

procedure TYutaniParticleEngine.InitGPUResources;
var csId, vsId, fsId: Cardinal;
    Positions, Velocities: array of TVector4; I: Integer;
begin
  if FGPUInitialized then Exit;
  if not LoadOpenGL43 then
    raise Exception.Create('Yutani.Render.Particles.GPU: OpenGL 4.3+ function pointers not available.');
  csId := CompileShaderRaw(COMPUTE_SHADER_SRC, GL_COMPUTE_SHADER);
  FComputeProgram := LinkProgramRaw([csId]);
  vsId := CompileShaderRaw(VERTEX_SHADER_SRC, GL_VERTEX_SHADER);
  fsId := CompileShaderRaw(FRAGMENT_SHADER_SRC, GL_FRAGMENT_SHADER);
  FRenderProgram := LinkProgramRaw([vsId, fsId]);
  FCompLoc_Time := glGetUniformLocation(FComputeProgram, 'time');
  FCompLoc_TimeScale := glGetUniformLocation(FComputeProgram, 'timeScale');
  FCompLoc_DeltaTime := glGetUniformLocation(FComputeProgram, 'deltaTime');
  FCompLoc_Sigma := glGetUniformLocation(FComputeProgram, 'sigma');
  FCompLoc_Rho := glGetUniformLocation(FComputeProgram, 'rho');
  FCompLoc_Beta := glGetUniformLocation(FComputeProgram, 'beta');
  FCompLoc_Mode := glGetUniformLocation(FComputeProgram, 'mode');
  FCompLoc_ParticleCount := glGetUniformLocation(FComputeProgram, 'particleCount');
  FCompLoc_PushPos := glGetUniformLocation(FComputeProgram, 'pushPos');
  FCompLoc_PushRadius := glGetUniformLocation(FComputeProgram, 'pushRadius');
  FCompLoc_PushStrength := glGetUniformLocation(FComputeProgram, 'pushStrength');
  FCompLoc_PushActive := glGetUniformLocation(FComputeProgram, 'pushActive');
  FCompLoc_EmColorR := glGetUniformLocation(FComputeProgram, 'emColorR');
  FCompLoc_EmColorG := glGetUniformLocation(FComputeProgram, 'emColorG');
  FCompLoc_EmColorB := glGetUniformLocation(FComputeProgram, 'emColorB');
  FCompLoc_EmColorA := glGetUniformLocation(FComputeProgram, 'emColorA');
  FCompLoc_GlobalWind := glGetUniformLocation(FComputeProgram, 'globalWind');
  FCompLoc_GlobalGravity := glGetUniformLocation(FComputeProgram, 'globalGravity');
  FRendLoc_ProjMatrix := glGetUniformLocation(FRenderProgram, 'projectionMatrix');
  FRendLoc_ViewMatrix := glGetUniformLocation(FRenderProgram, 'viewMatrix');
  FRendLoc_ParticleScale := glGetUniformLocation(FRenderProgram, 'particleScale');
  FRendLoc_EmColorR := glGetUniformLocation(FRenderProgram, 'emColorR');
  FRendLoc_EmColorG := glGetUniformLocation(FRenderProgram, 'emColorG');
  FRendLoc_EmColorB := glGetUniformLocation(FRenderProgram, 'emColorB');
  FRendLoc_EmColorA := glGetUniformLocation(FRenderProgram, 'emColorA');
  FRendLoc_EmSize := glGetUniformLocation(FRenderProgram, 'emSize');
  FRendLoc_HDRMultiplier := glGetUniformLocation(FRenderProgram, 'hdrMultiplier');
  SetLength(Positions, FNumParticles); SetLength(Velocities, FNumParticles);
  for I := 0 to FNumParticles - 1 do begin
    Positions[I].x := -1.0+Random*2.0; Positions[I].y := -1.0+Random*2.0; Positions[I].z := -1.0+Random*2.0; Positions[I].w := 0;
    Velocities[I].x := 0; Velocities[I].y := 0; Velocities[I].z := 0; Velocities[I].w := 0;
  end;
  glGenBuffers(1, @FSSBO_Positions);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, FSSBO_Positions);
  glBufferData(GL_SHADER_STORAGE_BUFFER, FNumParticles*SizeOf(TVector4), @Positions[0], GL_DYNAMIC_COPY);
  glGenBuffers(1, @FSSBO_Velocities);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, FSSBO_Velocities);
  glBufferData(GL_SHADER_STORAGE_BUFFER, FNumParticles*SizeOf(TVector4), @Velocities[0], GL_DYNAMIC_COPY);
  glGenBuffers(1, @FSSBO_StartPositions);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, FSSBO_StartPositions);
  glBufferData(GL_SHADER_STORAGE_BUFFER, FNumParticles*SizeOf(TVector4), @Positions[0], GL_DYNAMIC_COPY);
  glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
  BuildBillboardVAO;
  FGPUInitialized := True;
end;

procedure TYutaniParticleEngine.FreeGPUResources;
begin
  if not FGPUInitialized then Exit;
  if (FComputeProgram <> 0) and Assigned(glDeleteProgram) then glDeleteProgram(FComputeProgram);
  if (FRenderProgram <> 0) and Assigned(glDeleteProgram) then glDeleteProgram(FRenderProgram);
  if FSSBO_Positions <> 0 then glDeleteBuffers(1, @FSSBO_Positions);
  if FSSBO_Velocities <> 0 then glDeleteBuffers(1, @FSSBO_Velocities);
  if FSSBO_StartPositions <> 0 then glDeleteBuffers(1, @FSSBO_StartPositions);
  if FBillboardVBO <> 0 then glDeleteBuffers(1, @FBillboardVBO);
  if FBillboardVAO <> 0 then glDeleteVertexArrays(1, @FBillboardVAO);
  FComputeProgram := 0; FRenderProgram := 0;
  FSSBO_Positions := 0; FSSBO_Velocities := 0; FSSBO_StartPositions := 0;
  FBillboardVAO := 0; FBillboardVBO := 0;
  FGPUInitialized := False;
end;

procedure TYutaniParticleEngine.BuildBillboardVAO;
begin
  glGenVertexArrays(1, @FBillboardVAO);
  glBindVertexArray(FBillboardVAO);
  try
    glGenBuffers(1, @FBillboardVBO);
    glBindBuffer(GL_ARRAY_BUFFER, FBillboardVBO);
    glBufferData(GL_ARRAY_BUFFER, SizeOf(PARTICLE_VERTS), @PARTICLE_VERTS[0], GL_STATIC_DRAW);
    glVertexAttribPointer(0, 3, GL_FLOAT, 0, SizeOf(TVector3), nil);
    glEnableVertexAttribArray(0);
  finally glBindVertexArray(0); end;
end;

procedure TYutaniParticleEngine.Initialise;
begin
  if FGPUInitialized then Exit;
  FLock.Acquire;
  try InitGPUResources;
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.DispatchCompute(const dt: Single);
var GroupX: Cardinal; glErr: Cardinal;
begin
  rlDrawRenderBatchActive;
  rlSetShader(rlGetShaderIdDefault(), rlGetShaderLocsDefault());
  glUseProgram(FComputeProgram);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, FSSBO_Positions);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, FSSBO_Velocities);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, FSSBO_StartPositions);
  glUniform1f(FCompLoc_Time, FTime);
  glUniform1f(FCompLoc_TimeScale, FTimeScale);
  glUniform1f(FCompLoc_DeltaTime, dt);
  glUniform1f(FCompLoc_Sigma, FSigma);
  glUniform1f(FCompLoc_Rho, FRho);
  glUniform1f(FCompLoc_Beta, FBeta);
  glUniform1i(FCompLoc_Mode, FMode);
  glUniform1i(FCompLoc_ParticleCount, FNumParticles);
  glUniform3f(FCompLoc_PushPos, FPushPos.x, FPushPos.y, FPushPos.z);
  glUniform1f(FCompLoc_PushRadius, FPushRadius);
  glUniform1f(FCompLoc_PushStrength, FPushStrength);
  if FPushActive then glUniform1i(FCompLoc_PushActive, 1) else glUniform1i(FCompLoc_PushActive, 0);
  glUniform1f(FCompLoc_EmColorR, FEmColorR);
  glUniform1f(FCompLoc_EmColorG, FEmColorG);
  glUniform1f(FCompLoc_EmColorB, FEmColorB);
  glUniform1f(FCompLoc_EmColorA, FEmColorA);
  glUniform3f(FCompLoc_GlobalWind, FGlobalWind.x, FGlobalWind.y, FGlobalWind.z);
  glUniform3f(FCompLoc_GlobalGravity, FGlobalGravity.x, FGlobalGravity.y, FGlobalGravity.z);
  GroupX := Cardinal(FNumParticles div 1024);
  glDispatchCompute(GroupX, 1, 1);
  glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, 0);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, 0);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, 0);
  glUseProgram(0);
  rlSetShader(rlGetShaderIdDefault(), rlGetShaderLocsDefault());
  glErr := glGetError();
  if glErr <> GL_NO_ERROR then
    OutputDebugStringA(PAnsiChar(AnsiString(Format('Yutani GPU: GL error after compute = 0x%x', [glErr]))));
end;

procedure TYutaniParticleEngine.DrawInstances(const NumInstances: Integer; const ACamera: TCamera3D);
var ProjMat, ViewMat: TMatrix; glErr: Cardinal;
begin
  if NumInstances <= 0 then Exit;
  ViewMat := rlGetMatrixModelview(); ProjMat := rlGetMatrixProjection();
  rlDrawRenderBatchActive;
  glDisable(GL_CULL_FACE); glDepthMask(1); glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glUseProgram(FRenderProgram);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, FSSBO_Positions);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, FSSBO_Velocities);
  glUniformMatrix4fv(FRendLoc_ProjMatrix, 1, GL_TRUE, @ProjMat);
  glUniformMatrix4fv(FRendLoc_ViewMatrix, 1, GL_TRUE, @ViewMat);
  glUniform1f(FRendLoc_ParticleScale, FParticleScale);
  glUniform1f(FRendLoc_EmColorR, FEmColorR);
  glUniform1f(FRendLoc_EmColorG, FEmColorG);
  glUniform1f(FRendLoc_EmColorB, FEmColorB);
  glUniform1f(FRendLoc_EmColorA, FEmColorA);
  glUniform1f(FRendLoc_EmSize, FEmSize);
  glUniform1f(FRendLoc_HDRMultiplier, FHDRMultiplier);
  glBindVertexArray(FBillboardVAO);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 3, NumInstances);
  glBindVertexArray(0); glBindBuffer(GL_ARRAY_BUFFER, 0); glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
  glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, 0); glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, 0);
  glUseProgram(0);
  glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_2D, 0);
  rlSetShader(FRenderProgram, rlGetShaderLocsDefault());
  rlSetShader(rlGetShaderIdDefault(), rlGetShaderLocsDefault());
  glDisable(GL_BLEND); glDepthMask(1); glEnable(GL_CULL_FACE);
  rlDrawRenderBatchActive;
  glErr := glGetError();
  if glErr <> GL_NO_ERROR then
    OutputDebugStringA(PAnsiChar(AnsiString(Format('Yutani GPU: GL error after draw = 0x%x', [glErr]))));
end;

procedure TYutaniParticleEngine.Update(const ADeltaTime: Single);
begin
  if not FGPUInitialized then InitGPUResources;
  if FNumParticles = 0 then Exit;
  FLock.Acquire;
  try
    if FNeedsReset then begin
      FTime := 0; FNeedsReset := False; DispatchCompute(0);
    end else begin
      FTime := FTime + ADeltaTime; DispatchCompute(ADeltaTime);
    end;
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.Render(const ACamera: TCamera3D);
var NumInstances: Integer;
begin
  if not FGPUInitialized then InitGPUResources;
  NumInstances := Trunc(FInstancesX1000 / 1000.0 * FNumParticles);
  FLock.Acquire;
  try DrawInstances(NumInstances, ACamera);
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.Restart;
begin
  FLock.Acquire;
  try FNeedsReset := True;
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.Reset;
begin
  FLock.Acquire;
  try
    FTime := 0; FTimeScale := 0.2; FSigma := 10.0; FRho := 28.0;
    FBeta := 8.0/3.0; FParticleScale := 1.0; FInstancesX1000 := 1000.0;
    FMode := 0; FNeedsReset := True;
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.SetMode(AMode: Integer);
begin
  if AMode < 0 then AMode := 0;
  if AMode > 59 then AMode := 59;
  FLock.Acquire;
  try
    FMode := AMode;
    { Don't trigger FNeedsReset - let particles smoothly transition from
      their current positions to the new mode's behavior. Form modes (Cube,
      Sphere, DNA, Explode) use mix(pos, target, rate) which lerps smoothly.
      Motion modes (Lorenz, Wave, Galaxy, etc.) just apply their formula
      from the current pos/vel - the particles "break free" and flow into
      the new pattern. }
  finally
    FLock.Release;
  end;
end;

procedure TYutaniParticleEngine.SetPush(const APos: TVector3; ARadius, AStrength: Single);
begin
  FLock.Acquire;
  try
    FPushPos := APos; FPushRadius := ARadius; FPushStrength := AStrength; FPushActive := True;
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.ClearPush;
begin
  FLock.Acquire;
  try FPushActive := False;
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.SetEmColor(R, G, B, A: Single);
begin
  FLock.Acquire;
  try
    FEmColorR := R;
    FEmColorG := G;
    FEmColorB := B;
    FEmColorA := A;
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.SetEmSize(S: Single);
begin
  FLock.Acquire;
  try FEmSize := S;
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.SetGlobalWind(X, Y, Z: Single);
begin
  FLock.Acquire;
  try FGlobalWind := Vector3Create(X, Y, Z);
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.SetGlobalGravity(X, Y, Z: Single);
begin
  FLock.Acquire;
  try FGlobalGravity := Vector3Create(X, Y, Z);
  finally FLock.Release; end;
end;

procedure TYutaniParticleEngine.SetHDRMultiplier(M: Single);
begin
  FLock.Acquire;
  try FHDRMultiplier := M;
  finally FLock.Release; end;
end;

function TYutaniParticleEngine.GetActiveInstanceCount: Integer;
begin
  Result := Trunc(FInstancesX1000 / 1000.0 * FNumParticles);
end;

end.
