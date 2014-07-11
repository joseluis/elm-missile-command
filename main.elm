module MissileCommand where

import Mouse
import Random
import Window

type Pos = { x:Float, y:Float }
type Ms  = Float -- milliseconds

windowW      = 300
windowH      = 600
groundH      = 30   -- height of the ground
commandH     = 20   -- height of the command
missileStart = { x=0, y=-240 } -- coordinate from where friendly missiles are fired
speed        = 50   -- speed of missiles per second in a straight line
explosionSpd = 30   -- speed of the explosion per second
blastRadius  = 50   -- max radius of an explosion

type Velocity = { vx:Float, vy:Float }
type Radius   = Float
data Status   = Flying Pos Pos Velocity -- the starting, end positions and velocity of flight
              | Exploding Radius

type Missile   = { x:Float, y:Float, status:Status }
type GameState = { friendlyMissiles:[Missile], enemyMissiles:[Missile], score:Int, health:Int }

data Input = Time Ms                  -- time ticker
           | UserAction Pos           -- user action on the canvas
           | EnemyLaunch [(Pos, Pos)] -- enemy missile launches

defaultGame : GameState
defaultGame = { friendlyMissiles=[], enemyMissiles=[], score=0, health=100 }

filterJust : Maybe a -> Bool
filterJust x =
  case x of
    Just _ -> True
    _      -> False
    
extractJust : Maybe a -> a
extractJust x =
  case x of
    Just x' -> x'

choose : (a -> Maybe b) -> [a] -> [b]
choose f lst = map f lst |> filter filterJust |> map extractJust

calcVelocity : Pos -> Pos -> Velocity
calcVelocity start end = 
  let distH = end.x-start.x
      distV = end.y-start.y
      angle = atan2 distV distH
  in { vx=speed*cos angle, vy=speed*sin angle }
  
-- check if missile 1 is in the blast radius of missile 2
hitTest : Missile -> Missile -> Bool
hitTest missile1 missile2 =
  case (missile1.status, missile2.status) of
    (Flying _ _ _, Exploding radius) ->
      let (blastX, blastY) = (missile2.x, missile2.y)
          (minX, maxX, minY, maxY) = (blastX-radius, blastX+radius, blastY-radius, blastY+radius)
      in minX <= missile1.x 
         && missile1.x <= maxX 
         && minY <= missile1.y 
         && missile1.y <= maxY
    (_, _) -> False    

stepMissile : Float -> GameState -> Missile -> Maybe Missile
stepMissile delta { friendlyMissiles, enemyMissiles } missile =
  case missile.status of
    -- for a flying missile, move its position
    Flying _ end { vx, vy } -> 
      let newX    = missile.x + vx*delta
          newY    = missile.y + vy*delta
          inBlastRadius = any (hitTest missile) <| friendlyMissiles++enemyMissiles
          explode = if vy > 0 then newY > end.y else newY < end.y
      in if explode || inBlastRadius
         then Just { missile | x<-newX, y<-newY, status<-Exploding 0 }
         else Just { missile | x<-newX, y<-newY }
    -- for an exploding missile, expand the radius of the explosion
    Exploding radius -> 
      let newRadius = radius + explosionSpd*delta
          disappear = newRadius > blastRadius
      in if disappear 
         then Nothing
         else Just { missile | status<-Exploding newRadius }
         
newMissile : Pos -> Pos -> Missile
newMissile start end =
  let velocity = calcVelocity start end
  in Missile start.x start.y (Flying start end velocity)

stepGame : Input -> GameState -> GameState
stepGame input gameState =   
  case input of
    EnemyLaunch lst -> 
      let missiles = map (\(start, end) -> newMissile start end) lst
      in { gameState | enemyMissiles <- missiles++gameState.enemyMissiles }
    UserAction end -> 
      { gameState | friendlyMissiles <- newMissile missileStart end::gameState.friendlyMissiles }
    Time delta -> 
      let enemyMissiles    = choose (stepMissile delta gameState) gameState.enemyMissiles
          friendlyMissiles = choose (stepMissile delta gameState) gameState.friendlyMissiles
      in { gameState | enemyMissiles    <- enemyMissiles
                     , friendlyMissiles <- friendlyMissiles }

drawMissile : Missile -> Maybe Form
drawMissile { x, y, status } = 
  case status of
    Flying _ _ _ -> ngon 4 5 |> filled (rgb 255 0 0) |> move (x, y) |> Just
    _ -> Nothing
  
drawTrail : Missile -> Maybe Form
drawTrail { x, y, status } = 
  case status of
    Flying start _ _ ->
      path [ (x, y), (start.x, start.y) ] 
      |> traced (solid white)
      |> alpha 0.2
      |> Just
    _ -> Nothing
    
drawExplosions : Missile -> Maybe Form
drawExplosions { x, y, status } =
  case status of
    Exploding radius ->
      circle radius
      |> filled (rgb 150 170 150)
      |> alpha 0.5
      |> move (x, y)
      |> Just
    _ -> Nothing

display : GameState -> Element
display gameState =
  let (w, h) = (toFloat windowW, toFloat windowH)
  in collage windowW windowH
     <| concat [
          [ rect w h |> filled (rgb 20 0 20)
          , rect w groundH  |> filled (rgb 255 255 40)
                            |> move (0, -285)
          , ngon 3 commandH |> filled (rgb 255 255 40)
                            |> rotate (degrees 90)
                            |> move (0, -260) ],
                            
          choose drawExplosions gameState.friendlyMissiles,
          choose drawExplosions gameState.enemyMissiles,
          
          choose drawTrail gameState.friendlyMissiles,
          choose drawTrail gameState.enemyMissiles,
          
          choose drawMissile gameState.friendlyMissiles,
          choose drawMissile gameState.enemyMissiles
        ]

userInput : Signal Input
userInput = 
  -- converts the (x, y) coordinates of a mouse click to the coordinate system used by the collage
  let convert (w, h) (x, y) = (toFloat x - toFloat w/2, toFloat h/2 - toFloat y)
  in convert<~Window.dimensions~Mouse.position
     |> sampleOn Mouse.clicks
     |> lift (\(x, y) -> UserAction { x=x, y=y })
            
pairWise : [a] -> [(a, a)]
pairWise lst = 
  let loop lst acc = 
    case lst of
      a::b::tl -> loop tl ((a, b)::acc)
      [] -> acc
  in loop lst []
            
enemyLaunch : Signal Input
enemyLaunch =
  Random.range 0 5 (every <| 2*second) -- how many missiles to launch
  |> lift ((*) 2)                 -- every missile needs a pair of coordinates
  |> Random.floatList             -- turn each signal into n floats [0..1]
  |> lift (\lst -> pairWise lst
                   |> map (\(start, end) -> ({ x=600*start-300, y=300 }, { x=600*end-300, y=-270 }))
                   |> EnemyLaunch)

delta = fps 60
timer : Signal Input
timer = sampleOn delta <| (\n -> Time <| n / 1000)<~delta

input : Signal Input
input = merge timer userInput |> merge enemyLaunch

gameState : Signal GameState
gameState = foldp stepGame defaultGame input

main = display <~ gameState