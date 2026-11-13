{*******************************************************************************
  Yutani Render Gras - Sample Project
********************************************************************************
  Standalone VCL project that drops a 1,000,000-blade grass field on a
  20x20 ground patch and lets the user tweak field position, field size,
  blade size, wind and grass colors from the form.

  Compile this .dpr together with:
    - Unit1.pas            (the demo form)
    - uGrasEngine.pas      (threaded Raylib wrapper for grass)
    - Yutani.Render.Gras.pas (the GPU grass engine itself)

  Author: Lara Miriam Tamy Reschke / LamitaOne
*******************************************************************************}

program GrasDemo;

uses
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {Form1},
  uGrasEngine in 'uGrasEngine.pas',
  Yutani.Render.Gras in 'Yutani.Render.Gras.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskBar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
