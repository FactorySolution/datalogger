{
  ********************************************************************************

  Github - https://github.com/dliocode/datalogger

  ********************************************************************************

  MIT License

  Copyright (c) 2023 Danilo Lucas

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

  ********************************************************************************
}

unit DataLogger.Provider.ListBox;

interface

{$IF DEFINED(DATALOGGER_FMX) OR DEFINED(FRAMEWORK_FMX) OR NOT(DEFINED(LINUX))}

uses
  DataLogger.Provider, DataLogger.Types,
{$IF DEFINED(DATALOGGER_FMX) OR DEFINED(FRAMEWORK_FMX)}
  FMX.ListBox,
{$ELSE}
  Vcl.StdCtrls,
{$ENDIF}
  System.SysUtils, System.Classes, System.JSON, System.TypInfo;

type
{$SCOPEDENUMS ON}
  TListBoxModeInsert = (tmFirst, tmLast);
{$SCOPEDENUMS OFF}

  TProviderListBox = class(TDataLoggerProvider<TProviderListBox>)
  private
    FListBox: TCustomListBox;
    FMaxLogLines: Integer;
    FModeInsert: TListBoxModeInsert;
    FCleanOnStart: Boolean;
    FCleanOnRun: Boolean;
  protected
    procedure Save(const ACache: TArray<TLoggerItem>); override;
  public
    function ListBox(const AValue: TCustomListBox): TProviderListBox;
    function MaxLogLines(const AValue: Integer): TProviderListBox;
    function ModeInsert(const AValue: TListBoxModeInsert): TProviderListBox;
    function CleanOnStart(const AValue: Boolean): TProviderListBox;

    procedure LoadFromJSON(const AJSON: string); override;
    function ToJSON(const AFormat: Boolean = False): string; override;

    constructor Create;
  end;

{$ENDIF}

implementation

{$IF DEFINED(DATALOGGER_FMX) OR DEFINED(FRAMEWORK_FMX) OR NOT(DEFINED(LINUX))}

{ TProviderListBox }

constructor TProviderListBox.Create;
begin
  inherited Create;

  ListBox(nil);
  MaxLogLines(0);
  ModeInsert(TListBoxModeInsert.tmLast);
  CleanOnStart(False);
  FCleanOnRun := False;
end;

function TProviderListBox.ListBox(const AValue: TCustomListBox): TProviderListBox;
begin
  Result := Self;
  FListBox := AValue;
end;

function TProviderListBox.MaxLogLines(const AValue: Integer): TProviderListBox;
begin
  Result := Self;
  FMaxLogLines := AValue;
end;

function TProviderListBox.ModeInsert(const AValue: TListBoxModeInsert): TProviderListBox;
begin
  Result := Self;
  FModeInsert := AValue;
end;

function TProviderListBox.CleanOnStart(const AValue: Boolean): TProviderListBox;
begin
  Result := Self;
  FCleanOnStart := AValue;
end;

procedure TProviderListBox.LoadFromJSON(const AJSON: string);
var
  LJO: TJSONObject;
  LValue: string;
begin
  if AJSON.Trim.IsEmpty then
    Exit;

  try
    LJO := TJSONObject.ParseJSONValue(AJSON) as TJSONObject;
  except
    on E: Exception do
      Exit;
  end;

  if not Assigned(LJO) then
    Exit;

  try
    MaxLogLines(LJO.GetValue<Integer>('max_log_lines', FMaxLogLines));

    LValue := GetEnumName(TypeInfo(TListBoxModeInsert), Integer(FModeInsert));
    FModeInsert := TListBoxModeInsert(GetEnumValue(TypeInfo(TListBoxModeInsert), LJO.GetValue<string>('mode_insert', LValue)));

    CleanOnStart(LJO.GetValue<Boolean>('clean_on_start', FCleanOnStart));

    SetJSONInternal(LJO);
  finally
    LJO.Free;
  end;
end;

function TProviderListBox.ToJSON(const AFormat: Boolean): string;
var
  LJO: TJSONObject;
begin
  LJO := TJSONObject.Create;
  try
    LJO.AddPair('max_log_lines', TJSONNumber.Create(FMaxLogLines));
    LJO.AddPair('mode_insert', TJSONString.Create(GetEnumName(TypeInfo(TListBoxModeInsert), Integer(FModeInsert))));
    LJO.AddPair('clean_on_start', TJSONBool.Create(FCleanOnStart));

    ToJSONInternal(LJO);

    Result := TLoggerJSON.Format(LJO, AFormat);
  finally
    LJO.Free;
  end;
end;

procedure TProviderListBox.Save(const ACache: TArray<TLoggerItem>);
var
  LItem: TLoggerItem;
  LLog: string;
  LRetriesCount: Integer;
  LLines: Integer;
begin
  if not Assigned(FListBox) then
    raise EDataLoggerException.Create('ListBox not defined!');

  if (Length(ACache) = 0) then
    Exit;

  if not FCleanOnRun then
    if FCleanOnStart then
    begin
      FListBox.Clear;
      FCleanOnRun := True;
    end;

  for LItem in ACache do
  begin
    if LItem.InternalItem.IsSlinebreak then
      LLog := ''
    else
      LLog := TLoggerSerializeItem.AsString(FLogFormat, LItem, FFormatTimestamp, FIgnoreLogFormat, FIgnoreLogFormatSeparator, FIgnoreLogFormatIncludeKey, FIgnoreLogFormatIncludeKeySeparator);

    LRetriesCount := 0;

    while True do
      try
        if (csDestroying in FListBox.ComponentState) then
          Exit;

        try
          TThread.Synchronize(nil,
            procedure
            begin
              if (csDestroying in FListBox.ComponentState) then
                Exit;

              FListBox.Items.BeginUpdate;

              case FModeInsert of
                TListBoxModeInsert.tmFirst:
                  FListBox.Items.Insert(0, LLog);

                TListBoxModeInsert.tmLast:
                  FListBox.Items.Add(LLog);
              end;
            end);

          if (FMaxLogLines > 0) then
          begin
            TThread.Synchronize(nil,
              procedure
              begin
                if (csDestroying in FListBox.ComponentState) then
                  Exit;

                LLines := FListBox.Items.Count;

                case FModeInsert of
                  TListBoxModeInsert.tmFirst:
                    begin
                      while (LLines > FMaxLogLines) do
                      begin
                        FListBox.Items.Delete(Pred(LLines));
                        LLines := FListBox.Items.Count;
                      end;
                    end;

                  TListBoxModeInsert.tmLast:
                    begin
                      while (LLines > FMaxLogLines) do
                      begin
                        FListBox.Items.Delete(0);
                        LLines := FListBox.Items.Count;
                      end;
                    end;
                end;
              end);
          end;
        finally
          if not(csDestroying in FListBox.ComponentState) then
          begin
            TThread.Synchronize(nil,
              procedure
              begin
                if (csDestroying in FListBox.ComponentState) then
                  Exit;

                FListBox.Items.EndUpdate;

                case FModeInsert of
                  TListBoxModeInsert.tmFirst:
                    FListBox.ItemIndex := 0;

                  TListBoxModeInsert.tmLast:
                    FListBox.ItemIndex := FListBox.Items.Count - 1;
                end;
              end);
          end;
        end;

        Break;
      except
        on E: Exception do
        begin
          Inc(LRetriesCount);

          Sleep(50);

          if Assigned(FLogException) then
            FLogException(Self, LItem, E, LRetriesCount);

          if Self.Terminated then
            Exit;

          if (LRetriesCount <= 0) then
            Break;

          if (LRetriesCount >= FMaxRetries) then
            Break;
        end;
      end;
  end;
end;

procedure ForceReferenceToClass(C: TClass);
begin
end;

initialization

ForceReferenceToClass(TProviderListBox);

{$ENDIF}

end.
