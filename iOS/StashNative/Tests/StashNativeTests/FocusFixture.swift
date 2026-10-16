import XCTest
import RegressionSupport

enum FocusFixture {
    static func interactionSource() -> String {
        let source = StashNativeInteractionSource()!
        let probe = source.replacingOccurrences(of: "function revealFocus(){", with:
            "window.__stashTestFocusState=function(){return {queued:!!focusQueued,repairs:settleRepairs,settling:!!settleElement};};function revealFocus(){")
        XCTAssertNotEqual(source, probe, "The focus completion probe must match the production script")
        return probe
    }

    static let checkpointScript = """
    function waitForRendering(condition=()=>true){
      return new Promise((resolve,reject)=>{
        let frame=0,ready=0;
        const deadline=setTimeout(()=>{
          cancelAnimationFrame(frame);
          const state=window.__stashTestFocusState?.();
          reject(new Error('Focus fixture did not settle: '+JSON.stringify(state)));
        },30000);
        function check(){
          try{ready=condition()?ready+1:0;}
          catch(error){clearTimeout(deadline);reject(error);return;}
          if(ready===2){clearTimeout(deadline);resolve();}
          else frame=requestAnimationFrame(check);
        }
        frame=requestAnimationFrame(check);
      });
    }
    async function revealAndSettle(){
      await waitForRendering();
      window.__stashRevealFocusedElement();
      await waitForRendering(()=>{
        const state=window.__stashTestFocusState();
        if(!state.settling&&state.repairs===0)
          throw new Error('Focus reveal ended before its first rendering pass: '+JSON.stringify(state));
        return state.repairs>0&&!state.queued;
      });
    }

    """
}
