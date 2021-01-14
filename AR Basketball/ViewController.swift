//
//  ViewController.swift
//  AR Basketball
//
//  Created by Сергей on 01.12.2020.
//

import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, SCNPhysicsContactDelegate, UIGestureRecognizerDelegate {

    // MARK: - IBOutlets

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var scoreLabel: UILabel!
    
    // MARK: - Properties
    let maxBallsAllowed = 5
    var score = 0 {
        didSet {
            DispatchQueue.main.async {
                self.scoreLabel.text = "Score: \(self.score)"
            }
        }
    }
    let configuration = ARWorldTrackingConfiguration()
    var panStartLocation = CGPoint()
    var balls = [SCNNode]()
    
    var isFloorAdded = false {
        didSet {
            updatePlaneDetectionConfiguration()
        }
    }
    var isTargetHoopAdded = false {
        didSet {
            updatePlaneDetectionConfiguration()
        }
    }
    
    // MARK: - ViewController
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        sceneView.scene = SCNScene()
        sceneView.scene.physicsWorld.contactDelegate = self
        
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action:#selector(userPanned))
        panGestureRecognizer.delegate = self
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action:#selector(userTapped))
        tapGestureRecognizer.delegate = self
        
        // Pan to throw a ball
        sceneView.addGestureRecognizer(panGestureRecognizer)
        
        //Tap to set hoop or floor
        sceneView.addGestureRecognizer(tapGestureRecognizer)
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        configuration.planeDetection = [.horizontal, .vertical]

        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }

    // MARK: - Application methods

    func getDistance(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> CGFloat {
        let xDist = secondPoint.x - firstPoint.x;
        let yDist = secondPoint.y - firstPoint.y;
        return sqrt((xDist * xDist) + (yDist * yDist));
    }
    
    // Throwing a ball with different velocity
    func getBallNode(_ velocity: Float) -> SCNNode? {
        guard let frame = sceneView.session.currentFrame else {
            return nil
        }
        let cameraTransform = frame.camera.transform
        let cameraMatrixTransform = SCNMatrix4(cameraTransform)
        
        let power = velocity / 20
        let x = -cameraMatrixTransform.m31 * power
        let y = -cameraMatrixTransform.m32 * power
        let z = -cameraMatrixTransform.m33 * power
        let forceVector = SCNVector3(x, y, z)

        let ball = SCNSphere(radius: 0.125)
        ball.firstMaterial?.diffuse.contents = UIImage(named: "ball")
        
        let ballNode = SCNNode(geometry: ball)
        ballNode.physicsBody = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(node: ballNode))
        ballNode.physicsBody?.applyForce(forceVector, asImpulse: true)
        
        // Set parameters for ball to react with hoop, floor and count score point
        ballNode.physicsBody?.categoryBitMask = 1 << 1
        ballNode.physicsBody?.contactTestBitMask = 1 << 0
        ballNode.physicsBody?.collisionBitMask = 1 << 2 | 1 << 3 | 1 << 4
        
        ballNode.simdTransform = cameraTransform
        
        return ballNode
    }
    
    func getTargetHoopNode() -> SCNNode {
        let targetHoopNode = SCNNode()
        
        let board = SCNBox(width: 1.8, height: 1.05, length: 0.05, chamferRadius: 0.0)
        board.firstMaterial?.diffuse.contents = UIImage(named: "board")
        let boardNode = SCNNode(geometry: board)
        boardNode.physicsBody = SCNPhysicsBody(
            type: .static,
            shape: SCNPhysicsShape(
                node: boardNode,
                options: [
                    SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.concavePolyhedron
                ]
            )
        )
        boardNode.physicsBody?.categoryBitMask = 1 << 2
        boardNode.physicsBody?.collisionBitMask = 1 << 1
        
        let hoop = SCNTorus(ringRadius: 0.23, pipeRadius: 0.01)
        hoop.firstMaterial?.diffuse.contents = UIColor.orange
        let hoopNode = SCNNode(geometry: hoop)
        hoopNode.position = SCNVector3(0, -0.4, 0.267)
        hoopNode.physicsBody = SCNPhysicsBody(
            type: .static,
            shape: SCNPhysicsShape(
                node: hoopNode,
                options: [
                    SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.concavePolyhedron
                ]
            )
        )
        hoopNode.physicsBody?.categoryBitMask = 1 << 3
        hoopNode.physicsBody?.collisionBitMask = 1 << 1
        
        // Target point is not visible, a little bit under the hoop
        let targetPointGeometry = SCNSphere(radius: 0.000005)
        let targetPointNode = SCNNode(geometry: targetPointGeometry)
        targetPointNode.position = SCNVector3(0, -0.55, 0.267)
        targetPointNode.physicsBody = SCNPhysicsBody(
            type: .static,
            shape: SCNPhysicsShape(node: targetPointNode)
        )
        targetPointNode.physicsBody?.categoryBitMask = 1 << 0
        targetPointNode.physicsBody?.contactTestBitMask = 1 << 1
        
        targetHoopNode.addChildNode(boardNode)
        targetHoopNode.addChildNode(hoopNode)
        targetHoopNode.addChildNode(targetPointNode)
        
        return targetHoopNode.clone()
    }
    
    func getPlaneNode(for anchor: ARPlaneAnchor) -> SCNNode {
        let anchorExtent = anchor.extent
        let plane = SCNPlane(width: CGFloat(anchorExtent.x), height: CGFloat(anchorExtent.z))
        
        // Green color for walls, blue color for floor
        plane.firstMaterial?.diffuse.contents = anchor.alignment == .vertical ? UIColor.green : UIColor.blue

        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x -= .pi / 2
        planeNode.opacity = 0.25

        return planeNode
    }
    
    func resetGame() {
        isTargetHoopAdded = false
        isFloorAdded = false
        score = 0

        sceneView.scene.rootNode.enumerateChildNodes { (node, stop) in
            node.removeFromParentNode()
        }
    }
    
    // Change plane detection depending of what is set on scene
    func updatePlaneDetectionConfiguration() {
        if isFloorAdded && isTargetHoopAdded {
            configuration.planeDetection = []
        } else if !isFloorAdded && isTargetHoopAdded {
            configuration.planeDetection = [.horizontal]
        } else if isFloorAdded && !isTargetHoopAdded{
            configuration.planeDetection = [.vertical]
        } else if !isFloorAdded && !isTargetHoopAdded {
            configuration.planeDetection = [.horizontal, .vertical]
        }
        
        sceneView.session.run(configuration, options: .removeExistingAnchors)
    }
    
    func updatePlaneNode(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        guard let planeNode = node.childNodes.first, let plane = planeNode.geometry as? SCNPlane else {
            return
        }

        planeNode.simdPosition = anchor.center

        let anchorExtent = anchor.extent
        plane.width = CGFloat(anchorExtent.x)
        plane.height = CGFloat(anchorExtent.z)
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else {
            return
        }
        
        node.addChildNode(getPlaneNode(for: planeAnchor))
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else {
            return
        }
        
        updatePlaneNode(node, for: planeAnchor)
    }
    
    // MARK: - PhysicsWorld
    
    // Only contact between target point and ball is detected
    func physicsWorld(_ world: SCNPhysicsWorld, didEnd contact: SCNPhysicsContact) {
        score += 1
    }

    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      return true
    }
    
    // MARK: - IBActions
    @IBAction func resetGameClicked() {
        resetGame()
    }
    
    // Throw a ball on pan, velocity depends of pan distance
    @objc func userPanned(_ sender: UIPanGestureRecognizer) {
        if sender.state == .began {
            panStartLocation = sender.location(in: self.view)
        }
        if sender.state == .ended {
            let panEndLocation = sender.location(in: self.view)
            let velocity = getDistance(panStartLocation, panEndLocation)

            guard isTargetHoopAdded else {
                return
            }

            if balls.count == maxBallsAllowed {
                balls.removeFirst().removeFromParentNode()
            }
            
            guard let ballNode = getBallNode(Float(velocity)) else {
                return
            }

            balls.append(ballNode)
            sceneView.scene.rootNode.addChildNode(ballNode)
        }
    }
    
    @objc func userTapped(_ sender: UITapGestureRecognizer) {
        guard !isTargetHoopAdded else {
            return
        }

        let location = sender.location(in: sceneView)
        
        guard let result = sceneView.hitTest(location, types: .existingPlaneUsingExtent).first else {
            return
        }
        
        guard let anchor = result.anchor as? ARPlaneAnchor else {
            return
        }
        
        if anchor.alignment == .vertical && !isTargetHoopAdded {
            let targetHoopNode = getTargetHoopNode()
            targetHoopNode.simdTransform = result.worldTransform
            targetHoopNode.eulerAngles.x -= .pi / 2
            sceneView.scene.rootNode.addChildNode(targetHoopNode)

            isTargetHoopAdded = true
        }
        
        if anchor.alignment == .horizontal && !isFloorAdded {
            let horizontalPlaneNode = getPlaneNode(for: anchor)
            horizontalPlaneNode.name = "horizontalPlane"
            horizontalPlaneNode.physicsBody = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape())
            horizontalPlaneNode.physicsBody?.contactTestBitMask = 1 << 4
            horizontalPlaneNode.physicsBody?.collisionBitMask = 1 << 1
            sceneView.scene.rootNode.addChildNode(horizontalPlaneNode)
            
            isFloorAdded = true
        }
        
        
    }
}
