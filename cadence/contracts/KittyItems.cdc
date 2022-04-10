import NonFungibleToken from "./NonFungibleToken.cdc"
import MetadataViews from "./MetadataViews.cdc"

pub contract KittyItems: NonFungibleToken {

    // Events
    //
    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)
    pub event Minted(id: UInt64, kind: UInt8, rarity: UInt8, index: UInt64)

    // Named Paths
    //
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let MinterStoragePath: StoragePath

    // totalSupply
    // The total number of KittyItems that have been minted
    //
    pub var totalSupply: UInt64

    pub enum Rarity: UInt8 {
        pub case legendary
        pub case epic
        pub case common
    }

    pub fun rarityToString(_ rarity: Rarity): String {
        switch rarity {
            case Rarity.legendary:
                return "Legendary"
            case Rarity.epic:
                return "Epic"
            case Rarity.common:
                return "Common"
        }

        return ""
    }

    pub enum Kind: UInt8 {
        pub case kiddo
    }

    pub fun kindToString(_ kind: Kind): String {
        switch kind {
            case Kind.kiddo:
                return "Kiddo"
        }

        return ""
    }

    access(self) var legendaryImagesArray: [String]
    access(self) var epicImagesArray: [String]
    access(self) var commonImagesArray: [String]

    // Mapping from rarity -> price
    //
    access(self) var itemRarityPriceMap: {Rarity: UFix64}

    // Return the initial sale price for an item of this rarity.
    //
    pub fun getItemPrice(rarity: Rarity): UFix64 {
        return self.itemRarityPriceMap[rarity]!
    }
    
    // A Kitty Item as an NFT
    //
    pub resource NFT: NonFungibleToken.INFT, MetadataViews.Resolver {

        pub let id: UInt64

        // The token kind (e.g. Fishbowl)
        pub let kind: Kind

        // The token rarity (e.g. Gold)
        pub let rarity: Rarity

        // The token index
        pub let index: UInt64

        init(id: UInt64, kind: Kind, rarity: Rarity, index: UInt64) {
            self.id = id
            self.kind = kind
            self.rarity = rarity
            self.index = index
        }

        pub fun name(): String {
            return KittyItems.rarityToString(self.rarity)
                .concat(" ")
                .concat(KittyItems.kindToString(self.kind))
        }

        pub fun description(): String {
            return "A "
                .concat(KittyItems.rarityToString(self.rarity).toLower())
                .concat(" ")
                .concat(KittyItems.kindToString(self.kind).toLower())
                .concat(" with serial number ")
                .concat(self.id.toString())
        }

        pub fun imageCID(): String {
            if( self.rarity == Rarity.legendary)
            {
                return KittyItems.legendaryImagesArray[self.index]
            }
            else if( self.rarity == Rarity.epic)
            {
                return KittyItems.epicImagesArray[self.index]
            }
            else if( self.rarity == Rarity.common)
            {
                return KittyItems.commonImagesArray[self.index]
            }
            return KittyItems.commonImagesArray[0]
        }

        pub fun getViews(): [Type] {
            return [
                Type<MetadataViews.Display>()
            ]
        }

        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: self.name(),
                        description: self.description(),
                        thumbnail: MetadataViews.IPFSFile(
                            cid: self.imageCID(), 
                            path: "sm.png"
                        )
                    )
            }

            return nil
        }
    }

    // This is the interface that users can cast their KittyItems Collection as
    // to allow others to deposit KittyItems into their Collection. It also allows for reading
    // the details of KittyItems in the Collection.
    pub resource interface KittyItemsCollectionPublic {
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowKittyItem(id: UInt64): &KittyItems.NFT? {
            // If the result isn't nil, the id of the returned reference
            // should be the same as the argument to the function
            post {
                (result == nil) || (result?.id == id):
                    "Cannot borrow KittyItem reference: The ID of the returned reference is incorrect"
            }
        }
    }

    // Collection
    // A collection of KittyItem NFTs owned by an account
    //
    pub resource Collection: KittyItemsCollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
        // dictionary of NFT conforming tokens
        // NFT is a resource type with an `UInt64` ID field
        //
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        // withdraw
        // Removes an NFT from the collection and moves it to the caller
        //
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("missing NFT")

            emit Withdraw(id: token.id, from: self.owner?.address)

            return <-token
        }

        // deposit
        // Takes a NFT and adds it to the collections dictionary
        // and adds the ID to the id array
        //
        pub fun deposit(token: @NonFungibleToken.NFT) {
            let token <- token as! @KittyItems.NFT

            let id: UInt64 = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token

            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }

        // getIDs
        // Returns an array of the IDs that are in the collection
        //
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        // borrowNFT
        // Gets a reference to an NFT in the collection
        // so that the caller can read its metadata and call its methods
        //
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT
        }

        // borrowKittyItem
        // Gets a reference to an NFT in the collection as a KittyItem,
        // exposing all of its fields (including the typeID & rarityID).
        // This is safe as there are no functions that can be called on the KittyItem.
        //
        pub fun borrowKittyItem(id: UInt64): &KittyItems.NFT? {
            if self.ownedNFTs[id] != nil {
                let ref = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT
                return ref as! &KittyItems.NFT
            } else {
                return nil
            }
        }

        // destructor
        destroy() {
            destroy self.ownedNFTs
        }

        // initializer
        //
        init () {
            self.ownedNFTs <- {}
        }
    }

    // createEmptyCollection
    // public function that anyone can call to create a new empty collection
    //
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        return <- create Collection()
    }

    // NFTMinter
    // Resource that an admin or something similar would own to be
    // able to mint new NFTs
    //
    pub resource NFTMinter {

        // mintNFT
        // Mints a new NFT with a new ID
        // and deposit it in the recipients collection using their collection reference
        //
        pub fun mintNFT(
            recipient: &{NonFungibleToken.CollectionPublic}, 
            kind: Kind, 
            rarity: Rarity,
            index: UInt64,
        ) {
            // deposit it in the recipient's account using their reference
            recipient.deposit(token: <-create KittyItems.NFT(id: KittyItems.totalSupply, kind: kind, rarity: rarity, index: index))

            emit Minted(
                id: KittyItems.totalSupply,
                kind: kind.rawValue,
                rarity: rarity.rawValue,
                index: index,
            )

            KittyItems.totalSupply = KittyItems.totalSupply + (1 as UInt64)
        }
    }

    // fetch
    // Get a reference to a KittyItem from an account's Collection, if available.
    // If an account does not have a KittyItems.Collection, panic.
    // If it has a collection but does not contain the itemID, return nil.
    // If it has a collection and that collection contains the itemID, return a reference to that.
    //
    pub fun fetch(_ from: Address, itemID: UInt64): &KittyItems.NFT? {
        let collection = getAccount(from)
            .getCapability(KittyItems.CollectionPublicPath)!
            .borrow<&KittyItems.Collection{KittyItems.KittyItemsCollectionPublic}>()
            ?? panic("Couldn't get collection")
        // We trust KittyItems.Collection.borowKittyItem to get the correct itemID
        // (it checks it before returning it).
        return collection.borrowKittyItem(id: itemID)
    }

    // initializer
    //
    init() {
        // set rarity price mapping
        self.itemRarityPriceMap = {
            Rarity.legendary: 125.0,
            Rarity.epic: 25.0,
            Rarity.common: 5.0
        }

        self.legendaryImagesArray = ["bafybeihwuo24w6w54o3surwzbokisbyxbget5sykm7nmkcuzlxbajo2zzy","bafybeig7qtbrlfrddewa4ea5wswxx4j3jkjcwfmqybd4deuqntymfyumwy"]
        self.epicImagesArray = ["bafybeihwuo24w6w54o3surwzbokisbyxbget5sykm7nmkcuzlxbajo2zzy","bafybeig7qtbrlfrddewa4ea5wswxx4j3jkjcwfmqybd4deuqntymfyumwy"]
        self.commonImagesArray = ["bafybeihwuo24w6w54o3surwzbokisbyxbget5sykm7nmkcuzlxbajo2zzy", "bafybeig7qtbrlfrddewa4ea5wswxx4j3jkjcwfmqybd4deuqntymfyumwy"]

        // Set our named paths
        self.CollectionStoragePath = /storage/kittyItemsCollectionV10
        self.CollectionPublicPath = /public/kittyItemsCollectionV10
        self.MinterStoragePath = /storage/kittyItemsMinterV10

        // Initialize the total supply
        self.totalSupply = 0

        // Create a Minter resource and save it to storage
        let minter <- create NFTMinter()
        self.account.save(<-minter, to: self.MinterStoragePath)

        emit ContractInitialized()
    }
}
