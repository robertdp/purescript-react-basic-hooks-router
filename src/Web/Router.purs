module Web.Router
  ( module Types
  , makeRouter
  , override
  , redirect
  , continue
  , _Event
  , _Transitioning
  , _Resolved
  , isTransitioning
  , isResolved
  ) where

import Prelude
import Control.Monad.Free.Trans (liftFreeT, runFreeT)
import Data.Lens (Lens', Prism', is, lens, prism')
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (error, killFiber, launchAff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import Web.Router.Types (Command(..), Driver(..), Event(..), Resolved, Router, Transition(..), Transitioning)
import Web.Router.Types (Driver, Driver', Event(..), Resolved, Router, Transition, TransitionState, Transitioning) as Types

makeRouter ::
  forall i o.
  (Maybe i -> i -> Transition i o Transitioning Resolved Unit) ->
  (Event i -> Effect Unit) ->
  Driver i o ->
  Effect (Router o)
makeRouter onTransition onEvent (Driver driver) = do
  fiberRef <- Ref.new (pure unit)
  previousRouteRef <- Ref.new Nothing
  let
    runRouter route = do
      oldFiber <- Ref.read fiberRef
      launchAff_ (killFiber (error "Transition cancelled") oldFiber)
      previousRoute <- Ref.read previousRouteRef
      onEvent (Transitioning previousRoute route)
      let
        finalise r =
          liftEffect do
            Ref.write (Just r) previousRouteRef
            onEvent $ Resolved previousRoute r
      fiber <-
        launchAff case onTransition previousRoute route of
          Transition router ->
            router
              # runFreeT \cmd -> do
                  case cmd of
                    Redirect route' -> liftEffect do driver.redirect route'
                    Override route' -> finalise route'
                    Continue -> finalise route
                  mempty
      Ref.write fiber fiberRef
  pure { initialize: driver.initialize runRouter, navigate: driver.navigate, redirect: driver.redirect }

override :: forall i o. i -> Transition i o Transitioning Resolved Unit
override route = Transition (liftFreeT (Override route))

redirect :: forall i o. o -> Transition i o Transitioning Resolved Unit
redirect route = Transition (liftFreeT (Redirect route))

continue :: forall i o. Transition i o Transitioning Resolved Unit
continue = Transition (liftFreeT Continue)

_Event :: forall route. Lens' (Event route) route
_Event = lens getter setter
  where
  getter = case _ of
    Transitioning _ route -> route
    Resolved _ route -> route

  setter = case _ of
    Transitioning route _ -> Transitioning route
    Resolved route _ -> Resolved route

_Transitioning :: forall route. Prism' (Event route) route
_Transitioning =
  prism' (Transitioning Nothing) case _ of
    Transitioning _ route -> Just route
    _ -> Nothing

_Resolved :: forall route. Prism' (Event route) route
_Resolved =
  prism' (Resolved Nothing) case _ of
    Resolved _ route -> Just route
    _ -> Nothing

isTransitioning :: forall route. Event route -> Boolean
isTransitioning = is _Transitioning

isResolved :: forall route. Event route -> Boolean
isResolved = is _Resolved
